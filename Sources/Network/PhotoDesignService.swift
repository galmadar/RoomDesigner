import Foundation

/// `/upload` and `/compose` on the companion service: every picture goes up
/// first, then one call names them by the URLs that came back.
struct PhotoDesignService {

    struct Product: Encodable {
        let name: String
        let imageURL: String
        let marker: Marker?

        private enum CodingKeys: String, CodingKey { case name, imageURL = "image_url", marker }

        // An explicit null: the server reads a missing marker as a mistake, null as "not placed".
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(imageURL, forKey: .imageURL)
            try container.encode(marker, forKey: .marker)
        }
    }

    struct Request: Encodable {
        let prompt: String
        let model: PhotoDesignModel
        let roomPhotoURL: String?
        let scanURL: String
        let objects: [Product]
        let aspectRatio: String

        private enum CodingKeys: String, CodingKey {
            case prompt, model, roomPhotoURL = "room_photo_url", scanURL = "scan_url", objects,
                 aspectRatio = "aspect_ratio"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(prompt, forKey: .prompt)
            try container.encode(model.rawValue, forKey: .model)
            try container.encode(roomPhotoURL, forKey: .roomPhotoURL)
            try container.encode(scanURL, forKey: .scanURL)
            try container.encode(objects, forKey: .objects)
            try container.encode(aspectRatio, forKey: .aspectRatio)
        }
    }

    enum Failure: LocalizedError {
        /// The service's own explanation, written to be shown as is.
        case rejected(String)
        case unavailable(status: Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .rejected(let detail):
                return detail
            case .unavailable(404):
                return "Designing with photos isn't on the server yet. It needs the newest version of the service."
            case .unavailable:
                return "The picture couldn't be made just now. Please try again in a minute."
            case .unreadable:
                return "The picture came back but couldn't be read. Please try again."
            }
        }
    }

    /// Vercel refuses bodies over 4.5 MB, and base64 adds a third.
    static let maxUploadBytes = 3_000_000

    /// Nano Banana takes about 12 s and GPT-Image about 100 s; the server gives up at 280.
    static let composeTimeout: TimeInterval = 295

    private struct UploadRequest: Encodable {
        let image: String
        let contentType: String

        private enum CodingKeys: String, CodingKey { case image, contentType = "content_type" }
    }

    private struct UploadResponse: Decodable { let url: String }

    private struct ComposeResponse: Decodable {
        let images: [String]
        let model: String
    }

    func upload(_ data: Data, contentType: String) async throws -> String {
        let body = UploadRequest(image: data.base64EncodedString(), contentType: contentType)
        let reply = try await post("upload", body, timeout: 60)
        return try decode(UploadResponse.self, from: reply).url
    }

    /// The picture's URL and the endpoint that made it.
    func compose(_ request: Request) async throws -> (url: URL, endpoint: String) {
        let reply = try await post("compose", request, timeout: Self.composeTimeout)
        let decoded = try decode(ComposeResponse.self, from: reply)
        guard let url = decoded.images.first.flatMap(URL.init(string:)) else { throw Failure.unreadable }
        return (url, decoded.model)
    }

    func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard ((response as? HTTPURLResponse)?.statusCode ?? 200) < 300, !data.isEmpty else {
            throw Failure.unreadable
        }
        return data
    }

    // MARK: -

    private func post(_ path: String, _ body: some Encodable, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: PlanService.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Only these carry text meant for people; a framework 404 says just "Not Found".
            if [400, 413, 422].contains(status), let detail = Self.detail(in: data) {
                throw Failure.rejected(detail)
            }
            throw Failure.unavailable(status: status)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw Failure.unreadable }
    }

    /// FastAPI writes `detail` as a string for its own errors and as a list for validation ones.
    static func detail(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let text = object["detail"] as? String, !text.isEmpty { return text }
        if let list = object["detail"] as? [[String: Any]] {
            let messages = list.compactMap { $0["msg"] as? String }
            return messages.isEmpty ? nil : messages.joined(separator: "\n")
        }
        return nil
    }

    /// The system's wording for a dropped connection is technical; these say what to do.
    static func message(for error: Error) -> String {
        if let failure = error as? Failure { return failure.localizedDescription }
        switch (error as? URLError)?.code {
        case .timedOut?:
            return "That took too long, so the app stopped waiting. Please try again."
        case .notConnectedToInternet?, .networkConnectionLost?, .cannotConnectToHost?,
             .cannotFindHost?, .dataNotAllowed?:
            return "Can't reach the server. Check your connection and try again."
        default:
            return "Something went wrong while making the picture. Please try again."
        }
    }
}
