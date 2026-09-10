import Foundation

/// A furniture layout kept on purpose.
///
/// Undo covers a mistake; this covers the other thing — wanting to try something
/// completely different without losing the version you already liked.
struct Arrangement: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var savedAt: Date
    var proposals: [Proposal]

    init(name: String, proposals: [Proposal], savedAt: Date = .now) {
        self.name = name
        self.proposals = proposals
        self.savedAt = savedAt
    }
}
