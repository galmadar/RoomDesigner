import SwiftData
import SwiftUI

/// Starts a real picture on launch, so the notices can be driven on a simulator.
///
/// A notice only means anything once a run has actually settled, and there is
/// no way to tap a simulator from a script — so the run is started by name,
/// the same way ``RoomSeed`` opens a screen by name. Debug-only and opt-in:
/// with no environment set it does nothing.
struct PictureNoticeDrill: ViewModifier {
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
#if DEBUG
        content.task { start() }
#else
        content
#endif
    }

#if DEBUG
    @MainActor
    private func start() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MAKE_PICTURE"] == "1" else { return }

        // Never let the drill reach the paid service. An empty Settings field
        // falls back to the production address, so being pointed somewhere
        // local is checked rather than assumed.
        RoomSeed.pointAtLocalService()
        guard let host = PlanService.baseURLOverride?.host,
              host == "127.0.0.1" || host == "localhost" else { return }

        let name = environment["OPEN_ROOM"] ?? environment["SEED_ROOM_NAME"] ?? "Room 1"
        guard let room = try? context.fetch(
                  FetchDescriptor<ScannedRoom>(predicate: #Predicate { $0.name == name })).first,
              let captured = room.capturedRoom
        else { return }

        // The corrected scan already has them applied; applying them again
        // would move the same box twice.
        let bounds = RoomGeometry.build(from: captured).bounds
        let corner = SIMD2(bounds.min.x + 0.6, bounds.min.z + 0.6)

        PictureJobs.shared.start(
            .init(prompt: environment["MAKE_PICTURE_PROMPT"] ?? "A warmer room, in oak and wool.",
                  model: .nanoBanana, photoData: nil, photoThumbnail: nil,
                  angle: "Free angle", capturedRoom: captured, proposals: room.proposals,
                  markerColours: [:],
                  shot: PhotoDesignScene.freeShot(Camera.standing(at: corner, in: bounds)),
                  products: []),
            room: room, context: context)
    }
#endif
}
