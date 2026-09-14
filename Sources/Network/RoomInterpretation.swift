import Foundation

/// One sentence about the room, understood by the service.
///
/// Understanding is deliberately not done on the device. "That fridge is a
/// wardrobe, and it's wider than that" needs to resolve *which* thing and
/// *how much* wider against the room's own contents — and the one thing the
/// server must never do is guess a measurement, because a vague size comes back
/// as a question the user answers by tapping or by dragging on the plan.
enum RoomInterpretation {

    // MARK: - What goes up

    struct Request: Encodable {
        let sentence: String
        let room: Room

        struct Room: Encodable {
            let kind: String?
            let widthMetres: Float?
            let lengthMetres: Float?
            let objects: [Object]
        }

        struct Object: Encodable {
            let id: String
            let category: String
            let widthMetres: Float
            let depthMetres: Float
            let heightMetres: Float
        }
    }

    // MARK: - What comes back

    struct Reply: Decodable {
        /// Free text, or nil when the sentence said nothing about the room type.
        var roomKind: String?
        var objectEdits: [ObjectEdit] = []
        var questions: [Question] = []
        /// Plain sentences for anything the service did not act on, shown as
        /// written: an honest "I could not tell which thing you meant" beats a
        /// silent no-op.
        var unchanged: [String] = []

        var isEmpty: Bool {
            roomKind == nil && objectEdits.isEmpty && questions.isEmpty
        }
    }

    /// Fields are null when the sentence did not settle them, which is not the
    /// same as zero — a null leaves the scan's own measurement alone.
    struct ObjectEdit: Decodable, Identifiable {
        var id: String
        var category: String?
        var widthMetres: Float?
        var depthMetres: Float?
        var heightMetres: Float?
    }

    /// A vague size never arrives as an edit. It arrives here, with options to
    /// tap — and the plan is always the other way to answer it.
    ///
    /// Not guaranteed to arrive at all: where the room's geometry does not
    /// support two honest options the service drops the question and says so in
    /// `unchanged` instead, so a vague size can legitimately produce nothing.
    struct Question: Decodable, Identifiable {
        var id: String
        /// "widthMetres", "depthMetres" or "heightMetres".
        var field: String
        /// In the language the sentence was written in.
        var ask: String
        /// Computed from the room's geometry, so always English and always few.
        var options: [Option] = []

        struct Option: Decodable, Hashable {
            var label: String
            var value: Float
        }
    }

    /// The service's limits. Worth knowing on this side: a round trip that can
    /// only be refused is one the user waits through for nothing.
    static let maxSentenceCharacters = 1000
    static let maxObjects = 60

    enum Failure: LocalizedError {
        /// The endpoint is not deployed. Not an error the user caused, and not
        /// one that should stop them: every correction has a tappable form.
        case unavailable
        /// Refused for length — the sentence, or a room with too much in it.
        case toolong(String)
        case server(status: Int)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Saying it in words needs the newest version of the service. Tapping still works."
            case .toolong(let detail):
                return detail
            case .server:
                return "That could not be read just now. Tapping still works."
            }
        }
    }
}

extension PlanService {
    /// Sends one sentence and the room it is about.
    ///
    /// A 404 is called out separately from a real failure because it is the
    /// expected answer from a server that has not been updated yet, and the
    /// screen says so rather than blaming the sentence.
    func interpret(sentence: String,
                   room: RoomInterpretation.Request.Room) async throws -> RoomInterpretation.Reply {
        // Both limits are refusals, so they are caught here rather than waited on.
        if sentence.count > RoomInterpretation.maxSentenceCharacters {
            throw RoomInterpretation.Failure.toolong(
                "That is longer than the service will read. Try a sentence or two.")
        }
        if room.objects.count > RoomInterpretation.maxObjects {
            throw RoomInterpretation.Failure.toolong(
                "This scan has too much in it for the service to read a sentence against. Tapping still works.")
        }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("interpret"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Short on purpose: this is a convenience over tapping, and a minute
        // spent waiting for it is worse than tapping the answer.
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(
            RoomInterpretation.Request(sentence: sentence, room: room)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw RoomInterpretation.Failure.unavailable }
        if status == 422 {
            throw RoomInterpretation.Failure.toolong(
                "That was too long for the service to read. Try a shorter sentence.")
        }
        guard (200..<300).contains(status) else {
            throw RoomInterpretation.Failure.server(status: status)
        }
        return try JSONDecoder().decode(RoomInterpretation.Reply.self, from: data)
    }
}
