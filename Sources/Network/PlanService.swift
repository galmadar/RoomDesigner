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
        let count: Int
        let image: String            // base64 PNG
    }

    private struct Response: Decodable {
        let images: [String]         // URLs
    }

    private struct SuggestionRequest: Encodable {
        let room: RoomFacts
        let count: Int
    }

    private struct SuggestionResponse: Decodable {
        let suggestions: [String]
    }

    /// Two at a time: still a comparison, without paying four times over for Flux.
    static let conceptsPerRun = 2

    func generate(from image: UIImage, brief: Brief,
                  count: Int = conceptsPerRun) async throws -> [UIImage] {
        guard let png = image.pngData() else { throw Failure.badImage }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180        // generation routinely takes a minute
        request.httpBody = try JSONEncoder().encode(
            Request(prompt: brief.prompt,
                    strength: brief.strength,
                    conditioning: brief.conditioning.rawValue,
                    count: count,
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

    /// Design ideas for this particular room, from what the scan measured.
    ///
    /// The timeout is short on purpose: these are a convenience, and a minute
    /// spent waiting for them is worse than typing a brief yourself.
    func suggestions(for facts: RoomFacts, count: Int = 5) async throws -> [String] {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("suggest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(
            SuggestionRequest(room: facts, count: count)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.server(status: status,
                                 body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(SuggestionResponse.self, from: data).suggestions
    }

    // MARK: - Object library

    /// What the service found on a product page. The image URLs point at the
    /// shop, so the pictures are fetched by the device, not relayed.
    struct ImportedObject: Decodable {
        let title: String?
        let images: [String]
        let source: String?

        /// Strings rather than `[URL]` so one malformed address drops one picture, not the lot.
        var imageURLs: [URL] { images.compactMap(URL.init(string:)) }
    }

    enum ImportFailure: LocalizedError {
        /// The service's own explanation, written to be shown as is.
        case rejected(String)
        case unavailable(status: Int)

        var errorDescription: String? {
            switch self {
            case .rejected(let detail):
                return detail
            case .unavailable(404):
                return "Adding from a link isn't available on the server yet."
            case .unavailable(let status):
                return "The server couldn't read that page just now (error \(status))."
            }
        }
    }

    private struct ImportRequest: Encodable {
        let url: String
    }

    private struct ImportErrorBody: Decodable {
        let detail: String
    }

    func importObject(from url: URL) async throws -> ImportedObject {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("objects/import"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45         // the service fetches the shop's page first
        request.httpBody = try JSONEncoder().encode(ImportRequest(url: url.absoluteString))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Only these carry text meant for people; a framework 404 says just "Not Found".
            if [400, 422, 502].contains(status),
               let body = try? JSONDecoder().decode(ImportErrorBody.self, from: data),
               !body.detail.isEmpty {
                throw ImportFailure.rejected(body.detail)
            }
            throw ImportFailure.unavailable(status: status)
        }
        return try JSONDecoder().decode(ImportedObject.self, from: data)
    }
}
