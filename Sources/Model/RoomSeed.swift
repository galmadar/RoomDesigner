import Foundation
import RoomPlan
import SwiftData
import SwiftUI

/// Puts a room into the store without a scan, so the app can be driven on a
/// simulator.
///
/// Scanning needs a LiDAR device, and real scans are the layout of somebody's
/// home and stay on their phone. Debug-only and opt-in: nothing here is
/// compiled into a release build, and with no environment set it does nothing.
enum RoomSeed {

#if DEBUG
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Where requests go. Set alongside the room so a driven app can never be
    /// pointed at the paid service by an empty Settings field, which falls back
    /// to the built-in production address rather than to nothing.
    static func pointAtLocalService() {
        guard let address = environment["SERVER_BASE_URL"],
              let url = URL(string: address) else { return }
        PlanService.baseURLOverride = url
    }

    /// A base64 `CapturedRoom`, inserted once under the given name.
    @MainActor
    static func installIfAsked(into context: ModelContext) {
        pointAtLocalService()

        guard let encoded = environment["SEED_ROOM"],
              let data = Data(base64Encoded: encoded),
              let room = try? JSONDecoder().decode(CapturedRoom.self, from: data)
        else { return }

        let name = environment["SEED_ROOM_NAME"] ?? "Room 1"
        let existing = try? context.fetch(
            FetchDescriptor<ScannedRoom>(predicate: #Predicate { $0.name == name }))
        guard existing?.isEmpty ?? true else { return }

        let seeded = ScannedRoom(name: name)
        seeded.capturedRoom = room
        if let corrections = environment["SEED_CORRECTIONS"],
           let data = Data(base64Encoded: corrections),
           let decoded = try? JSONDecoder().decode(RoomCorrections.self, from: data) {
            seeded.corrections = decoded
        }
        context.insert(seeded)
    }

    // MARK: - Reaching a screen without a finger

    /// There is no way to tap a simulator from a script, so the screens under
    /// test are opened by name instead.
    static var opensIdentity: Bool { environment["SEED_OPEN_IDENTITY"] == "1" }

    /// "object", "size" or "ideas" — pushed on top of the guess screen.
    static var route: String? { environment["SEED_ROUTE"] }

    /// Sent through the real endpoint on appear, so the talk screen is driven
    /// by an actual round trip rather than a hand-made reply.
    static var sentence: String? { environment["SEED_SENTENCE"] }

    /// Opens "See the scan", which renders the mesh through the same `Renderer`
    /// the conditioning image comes from — so a correction can be shown
    /// reaching the geometry rather than only the labels.
    static var opensScan: Bool { environment["SEED_OPEN_SCAN"] == "1" }
#else
    static var opensIdentity: Bool { false }
    static var route: String? { nil }
    static var sentence: String? { nil }
    static var opensScan: Bool { false }
#endif
}

/// Hangs the seeding off the app's one window, which is the only place with a
/// model context before any screen appears.
struct RoomSeeding: ViewModifier {
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
#if DEBUG
        content.task { RoomSeed.installIfAsked(into: context) }
#else
        content
#endif
    }
}
