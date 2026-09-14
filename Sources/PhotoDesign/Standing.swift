import Foundation
import simd

/// Where someone is standing and how they are seeing it — carried out of the
/// walk and into the design flow, so a picture can be made of exactly the view
/// they were looking at.
///
/// The position has already been held inside the floor polygon by
/// ``RoomFloor/keepInside(_:margin:)``. Nothing downstream may clamp it again
/// to a bounding box: a room scanned at an angle overhangs its own box, and
/// clamping to one can push a camera that was inside the room back out of it.
struct Standing: Identifiable {
    let id = UUID()

    /// World (x, z), as `FloorPlan` and `Camera.standing` use it.
    var position: SIMD2<Float>
    var yaw: Float
    var pitch: Float
    /// Above the floor, not above the world.
    var eyeHeight: Float
    /// World y of the floor, so the eye lands where the walk had it.
    var level: Float
    var fieldOfView: Float

    /// The same expression ``WalkState/camera`` builds, so the picture is taken
    /// through the camera that was on screen rather than one near it.
    var camera: Camera {
        let eye = SIMD3(position.x, level + eyeHeight, position.y)
        let direction = SIMD3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        return Camera(eye: eye, target: eye + direction, fieldOfView: fieldOfView)
    }
}
