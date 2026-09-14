import Foundation
import SwiftData
import SwiftUI

/// Design ideas for a room, and the rule that they belong to a room *type*.
///
/// Ideas are cheap text, so the moment the room stops being a kitchen the
/// kitchen ideas are thrown out and fetched again. Pictures are not: they cost
/// money and a wait, and they are left exactly where they are with a line
/// saying what they were made as.
///
/// Owned by the app rather than by a screen, because the correction happens on
/// one screen and the ideas are read on another.
@MainActor
final class RoomIdeas: ObservableObject {
    static let shared = RoomIdeas()

    struct State {
        var ideas: [String] = []
        /// The room type these ideas were asked for, so a change invalidates them.
        var askedFor: String?
        var isLoading = false
        var hasAsked = false
        var failed = false
    }

    @Published private(set) var states: [PersistentIdentifier: State] = [:]

    private init() {}

    func state(for room: ScannedRoom) -> State {
        states[room.persistentModelID] ?? State()
    }

    /// Throws away what is on screen and asks again. Called the instant the
    /// room type changes, so the new ideas are already arriving by the time the
    /// user reaches them.
    func roomKindChanged(_ room: ScannedRoom) {
        states[room.persistentModelID] = State()
        Task { await load(room) }
    }

    /// Fetched once per room type. The screen opens often and a network call
    /// every time would buy nothing.
    func load(_ room: ScannedRoom, force: Bool = false) async {
        let id = room.persistentModelID
        guard let captured = room.rawCapturedRoom else { return }
        let reading = room.reading(of: captured)
        let kind = reading.kind

        var current = state(for: room)
        if !force, current.hasAsked, current.askedFor == kind, !current.ideas.isEmpty { return }
        guard !current.isLoading else { return }

        current.isLoading = true
        current.failed = false
        states[id] = current

        let facts = RoomFacts(reading: reading, of: captured)
        // Deliberately no alert: a missing idea is not an error the user has to
        // deal with, it just means typing the brief instead.
        let fetched = (try? await PlanService().suggestions(for: facts)) ?? []

        var settled = state(for: room)
        settled.isLoading = false
        settled.hasAsked = true
        settled.askedFor = kind
        settled.ideas = fetched
        settled.failed = fetched.isEmpty
        states[id] = settled
    }
}
