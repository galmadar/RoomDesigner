import ARKit
import RoomPlan
import SwiftUI
import simd

/// Live coaching against the real capture session.
///
/// Everything said here is RoomPlan's own reading: its `Instruction` stream for
/// the corrections, and the live `CapturedRoom` for which walls it has found and
/// which of them it has not yet joined into their corners. Nothing is inferred
/// from the phone's motion — the framework already measures that, and a second
/// opinion would only disagree with the one the user is being shown.
@MainActor
final class ScanCoach: ObservableObject {

    /// The one line of correction on screen. Never two at once.
    struct Correction: Equatable, Sendable {
        let title: String
        let detail: String
    }

    /// The little the overlay needs, worked out off the main thread so the
    /// capture session never waits on SwiftUI.
    struct Progress: Equatable, Sendable {
        var found = 0
        var joined = 0
        /// World position of a vertical wall edge RoomPlan has not closed yet.
        var openCorner: SIMD3<Float>?
    }

    @Published private(set) var progress = Progress()
    @Published private(set) var correction: Correction?
    /// Where the unjoined corner falls in the upright camera image, 0...1 from
    /// the top left, and that image's aspect. Nil whenever it is off screen.
    @Published private(set) var aim: CGPoint?
    @Published private(set) var aimAspect: CGFloat = 4.0 / 3.0

    private weak var view: RoomCaptureView?
    private var correctionShownAt = Date.distantPast

    /// A correction that vanishes the instant RoomPlan stops complaining reads
    /// as a flicker rather than as advice.
    private static let minimumDwell: TimeInterval = 1.8

    var unjoined: Int { max(0, progress.found - progress.joined) }

    func attach(to view: RoomCaptureView, recorder: LiveRoomRecorder) {
        self.view = view
        recorder.observe(
            progress: { [weak self] progress in
                Task { @MainActor in self?.progress = progress }
            },
            correction: { [weak self] correction in
                Task { @MainActor in self?.show(correction) }
            })
    }

    private func show(_ incoming: Correction?) {
        guard let incoming else {
            // Let the last one stand its minimum before clearing it.
            if Date.now.timeIntervalSince(correctionShownAt) >= Self.minimumDwell { correction = nil }
            return
        }
        guard incoming != correction else { return }
        correction = incoming
        correctionShownAt = .now
    }

    /// Projects the unjoined corner through the live AR camera. Called on a
    /// timer rather than per frame: it only has to be roughly where the corner
    /// is, and it must never be the reason a capture stutters.
    #if DEBUG
    private var isStandIn = false

    /// Fabricated live state, so the coaching can be seen on a simulator that
    /// has no LiDAR and therefore no capture session to coach.
    func standIn(found: Int, joined: Int, correction: Correction?, aim: CGPoint?) {
        isStandIn = true
        progress = Progress(found: found, joined: joined, openCorner: nil)
        self.correction = correction
        self.aim = aim
    }
    #endif

    func refreshAim() {
        #if DEBUG
        if isStandIn { return }
        #endif
        guard let corner = progress.openCorner, let view,
              let frame = view.captureSession.arSession.currentFrame
        else { return aim = nil }

        var held = view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        if held == .unknown { held = .portrait }

        let camera = frame.camera
        let viewpoint = PhotoViewpoint(
            transform: camera.transform,
            intrinsics: camera.intrinsics,
            imageResolution: SIMD2(Float(camera.imageResolution.width),
                                   Float(camera.imageResolution.height)),
            orientation: PhotoOrientation(held))

        let size = viewpoint.uprightSize
        guard size.x > 0, size.y > 0, let pixel = viewpoint.pixel(corner) else { return aim = nil }

        let point = CGPoint(x: CGFloat(pixel.x / size.x), y: CGFloat(pixel.y / size.y))
        // Only worth drawing while it is actually in frame.
        guard (-0.1...1.1).contains(point.x), (-0.1...1.1).contains(point.y) else { return aim = nil }
        aim = point
        aimAspect = CGFloat(size.x / size.y)
    }

    // MARK: - Reading RoomPlan, off the main thread

    nonisolated static func correction(for instruction: RoomCaptureSession.Instruction) -> Correction? {
        switch instruction {
        case .slowDown:
            return Correction(title: "Slow down",
                              detail: "Sweep along the wall — don't swing past it.")
        case .moveCloseToWall:
            return Correction(title: "Closer to the wall",
                              detail: "It is too far away to read from here.")
        case .moveAwayFromWall:
            return Correction(title: "Step back",
                              detail: "Too close to see the whole wall at once.")
        case .turnOnLight:
            return Correction(title: "Too dark",
                              detail: "Turn a light on — it cannot find a wall it cannot see.")
        case .lowTexture:
            return Correction(title: "Nothing to hold on to",
                              detail: "A bare wall is hard to read. Move along it slowly.")
        case .normal:
            return nil
        @unknown default:
            return nil
        }
    }

    nonisolated static func progress(of room: CapturedRoom) -> Progress {
        var result = Progress()
        var widest: Float = 0
        for wall in room.walls {
            result.found += 1
            let open = Set(CapturedRoom.Surface.Edge.allCases).subtracting(wall.completedEdges)
            // Left and right are a wall's vertical edges: its corners.
            guard !open.isDisjoint(with: [.left, .right]) else { result.joined += 1; continue }
            guard wall.dimensions.x > widest else { continue }
            widest = wall.dimensions.x
            // The open side itself, at mid height — the corner to walk back to.
            let half = wall.dimensions.x / 2
            let side = open.contains(.left) ? -half : half
            let world = wall.transform * SIMD4<Float>(side, 0, 0, 1)
            result.openCorner = SIMD3(world.x, world.y, world.z)
        }
        return result
    }
}
