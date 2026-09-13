import RoomPlan
import SwiftUI
import simd

/// Where you are standing in the scanned room, and everything that moves it.
///
/// The values a frame reads — position, yaw, pitch — are deliberately not
/// published: a finger moving produces sixty of them a second, and none of them
/// is a reason to rebuild a SwiftUI view. Only what the chrome shows is.
@MainActor
final class WalkState: ObservableObject {

    /// Metres a second at full stick. A slow walk on purpose: these rooms are
    /// four metres across, and anything brisker overshoots the far wall.
    static let speed: Float = 1.3
    static let lowestEye: Float = 0.6
    static let highestEye: Float = 2.0
    /// Kept off the walls, so you never end up inside one looking at its back.
    static let wallMargin: Float = 0.3
    static let lookRate: Float = 0.006

    @Published private(set) var isReady = false
    @Published private(set) var hasRoom = false
    @Published private(set) var eyeHeight: Float = 1.6
    /// The photo you are standing at, until you move off it.
    @Published private(set) var standingAt: Int?

    private(set) var renderer: WalkRenderer?

    var yaw: Float = 0
    var pitch: Float = 0
    var position: SIMD2<Float> = .zero
    /// Stick, −1…1 each way; y is forward.
    var walk: SIMD2<Float> = .zero
    var fieldOfView: Float = 65 * .pi / 180
    /// Set while a photo is being compared: its exact pose, roll and lens.
    var pinned: Camera?

    private var floor: RoomFloor?
    private var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) = (.zero, .zero)

    // MARK: - Opening the room

    /// Decoding the scan and building the mesh happen once, off the main thread;
    /// the room is then fixed for the life of the screen.
    func load(_ room: ScannedRoom) async {
        guard !isReady else { return }
        let scan = room.capturedRoomData
        let proposals = room.proposals

        let built = await Task.detached(priority: .userInitiated) { () -> (Mesh, RoomFloor?)? in
            guard let scan,
                  let captured = try? JSONDecoder().decode(CapturedRoom.self, from: scan)
            else { return nil }
            return (RoomGeometry.build(from: captured, proposals: proposals),
                    RoomFloor(room: captured))
        }.value

        guard let (mesh, floor) = built, !mesh.isEmpty else {
            isReady = true
            return
        }

        self.floor = floor
        bounds = mesh.bounds
        standAtOpening()

        let renderer = WalkRenderer(mesh: mesh)
        renderer?.pose = { [weak self] seconds in
            guard let self else { return Camera(eye: .zero, target: SIMD3(0, 0, -1)) }
            self.advance(seconds)
            return self.camera
        }
        self.renderer = renderer
        hasRoom = renderer != nil
        isReady = true
    }

    /// The floor polygon decides where you start, never the bounding box: a room
    /// scanned at an angle has box corners outside its own walls.
    private func standAtOpening() {
        // Level at eye height is a bare wall filling the frame; the design flow's
        // free camera tips the same 8°, and the floor is what says "room".
        pitch = -8 * .pi / 180
        guard let floor else {
            position = Camera.centre(of: bounds)
            return
        }
        position = floor.deepestPoint
        yaw = floor.heading(from: position)
    }

    // MARK: - Standing

    private var level: Float { floor?.level ?? bounds.min.y }
    private var ceiling: Float { floor?.ceiling ?? bounds.max.y }

    var camera: Camera {
        if let pinned { return pinned }
        let height = min(level + eyeHeight, ceiling - 0.1)
        let eye = SIMD3(position.x, height, position.y)
        let direction = SIMD3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        return Camera(eye: eye, target: eye + direction, fieldOfView: fieldOfView)
    }

    /// Whether walking is held inside the walls at all — false for a scan with
    /// no floor surface, where there is no outline to test against.
    var stopsAtWalls: Bool { floor != nil }

    // MARK: - Moving

    func advance(_ seconds: Float) {
        guard pinned == nil, simd_length_squared(walk) > 1e-6 else { return }
        let forward = SIMD2(sin(yaw), -cos(yaw))
        let right = SIMD2(-forward.y, forward.x)
        move(to: position + (forward * walk.y + right * walk.x) * (Self.speed * seconds))
    }

    func look(by delta: CGSize) {
        guard pinned == nil else { return }
        yaw += Float(delta.width) * Self.lookRate
        // Short of straight up or down, where a view matrix has no heading left.
        pitch = simd_clamp(pitch - Float(delta.height) * Self.lookRate, -1.4, 1.4)
    }

    func setEyeHeight(_ metres: Float) {
        eyeHeight = simd_clamp(metres, Self.lowestEye, Self.highestEye)
        leaveSpot()
    }

    private func move(to spot: SIMD2<Float>) {
        position = floor?.keepInside(spot, margin: Self.wallMargin) ?? spot
        leaveSpot()
    }

    private func leaveSpot() {
        // Only on a real change: this runs inside the draw loop.
        if standingAt != nil { standingAt = nil }
    }

    // MARK: - Photo spots

    /// The pose the photo was taken from — the same spot, the same way, the same
    /// lens. Barely nudged off the walls: whoever took it may have stood close.
    func stand(at photo: ScanPhoto, index: Int) {
        guard let viewpoint = photo.viewpoint else { return }
        let spot = viewpoint.planSpot
        pinned = nil
        position = floor?.keepInside(spot.position, margin: 0.05) ?? spot.position
        yaw = spot.yaw
        pitch = spot.pitch
        eyeHeight = simd_clamp(spot.height - level, Self.lowestEye, Self.highestEye)
        fieldOfView = viewpoint.verticalFieldOfView
        standingAt = index
    }

    /// Exactly the photo's camera, roll included, for holding the two side by side.
    func compare(with photo: ScanPhoto?) {
        pinned = photo?.camera
    }
}
