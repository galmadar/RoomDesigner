import UIKit

/// Talks to the thin Python service that holds the API keys.
///
/// The keys stay off the device deliberately: it means the prompt and the model
/// choice can change without shipping a new build.
struct PlanService {

    struct Brief {
        var prompt: String
        var strength: Float = 1.0
        var conditioning: ConditioningImages.Kind = .depth
    }

    enum Failure: LocalizedError {
        case badImage
        case server(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .badImage:
                return "The rendered image could not be encoded."
            case .server(let status, let body):
                return "The server returned \(status). \(body)"
            }
        }
    }

    /// The deployed companion service, built in so that a fresh install — and a
    /// second device — can generate without anyone visiting Settings first.
    static let defaultBaseURL = URL(string: "https://room-designer-server.vercel.app")!

    /// An address typed in Settings, or nil to fall back to ``defaultBaseURL``.
    /// Assigning nil forgets the override rather than storing something empty.
    static var baseURLOverride: URL? {
        get { UserDefaults.standard.url(forKey: "serverBaseURL") }
        set {
            guard let newValue else {
                return UserDefaults.standard.removeObject(forKey: "serverBaseURL")
            }
            UserDefaults.standard.set(newValue, forKey: "serverBaseURL")
        }
    }

    /// Where requests actually go. Non-optional: there is always somewhere to ask.
    static var baseURL: URL { baseURLOverride ?? defaultBaseURL }

    private struct Request: Encodable {
        let prompt: String
        let strength: Float
        let conditioning: String
        let image: String            // base64 PNG
    }

    private struct Response: Decodable {
        let images: [String]         // URLs
    }

    func generate(from image: UIImage, brief: Brief) async throws -> [UIImage] {
        guard let png = image.pngData() else { throw Failure.badImage }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180        // generation routinely takes a minute
        request.httpBody = try JSONEncoder().encode(
            Request(prompt: brief.prompt,
                    strength: brief.strength,
                    conditioning: brief.conditioning.rawValue,
                    image: png.base64EncodedString())
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.server(status: status,
                                 body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return try await withThrowingTaskGroup(of: UIImage?.self) { group in
            for urlString in decoded.images {
                guard let url = URL(string: urlString) else { continue }
                group.addTask {
                    let (bytes, _) = try await URLSession.shared.data(from: url)
                    return UIImage(data: bytes)
                }
            }
            var images: [UIImage] = []
            for try await image in group { if let image { images.append(image) } }
            return images
        }
    }
}
