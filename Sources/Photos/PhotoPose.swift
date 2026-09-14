import UIKit
import simd

/// Builds a `PhotoViewpoint` for a photograph that arrived without one.
///
/// A photo from the camera roll carries no record of where the photographer
/// stood and usually no usable lens either, so both have to be supplied: the
/// pose from where the user stands the camera on the plan, or from ARKit in a
/// session relocalised against the scan's own world map; the lens from the
/// angle of view they choose. What comes out is an ordinary `PhotoViewpoint`,
/// so every screen that can read a scanned photo reads a placed one the same
/// way — the plan's spots, the walk's compare, the design flow's shot.
///
/// The convention is `PhotoViewpoint`'s: ARKit camera space, +X right, +Y up,
/// looking down −Z. The stored image is already upright, so `orientation` is
/// `.landscapeRight` — the identity as far as `upright(native:)` goes — and
/// `imageResolution` is the upright pixel size whichever way round the photo is.
enum PhotoPose {

    /// The steepest a placed photo may be tipped. Straight up or down leaves a
    /// view matrix with no heading, and no photograph of a room needs it.
    static let steepestPitch: Float = 80 * .pi / 180

    /// Where a photo stands, in the terms the plan already speaks.
    struct Placing: Equatable {
        /// World (x, z), as `FloorPlan` and `Camera.standing` use it.
        var position: SIMD2<Float> = .zero
        var yaw: Float = 0
        var pitch: Float = 0
        /// Above the floor, not above the world.
        var eyeHeight: Float = 1.5
        /// World y of the floor, so the lens lands inside the room.
        var level: Float = 0
        /// Across the photograph, which is the number the lens control shows.
        var horizontalFieldOfView: Float = 65 * .pi / 180
    }

    static func viewpoint(_ placing: Placing, imageSize: SIMD2<Float>) -> PhotoViewpoint? {
        let pitch = min(max(placing.pitch, -steepestPitch), steepestPitch)
        let eye = SIMD3(placing.position.x, placing.level + placing.eyeHeight,
                        placing.position.y)
        let forward = SIMD3(sin(placing.yaw) * cos(pitch), sin(pitch),
                            -cos(placing.yaw) * cos(pitch))
        return viewpoint(eye: eye, forward: forward, imageSize: imageSize,
                         horizontalFieldOfView: placing.horizontalFieldOfView)
    }

    /// The shared builder: a lens at `eye` looking along `forward`, levelled.
    ///
    /// Roll is dropped on purpose. An uploaded photograph is held level almost
    /// without exception, and a wrong roll is the one error that makes a
    /// cross-fade impossible to judge — the walls tilt against each other and
    /// nothing can be brought into line by moving.
    static func viewpoint(eye: SIMD3<Float>, forward direction: SIMD3<Float>,
                          imageSize: SIMD2<Float>,
                          horizontalFieldOfView: Float) -> PhotoViewpoint? {
        guard imageSize.x > 0, imageSize.y > 0,
              simd_length(direction) > 1e-5 else { return nil }
        let forward = simd_normalize(direction)

        var up = SIMD3<Float>(0, 1, 0)
        if abs(simd_dot(forward, up)) > 0.999 { up = SIMD3(0, 0, 1) }
        let right = simd_normalize(simd_cross(forward, up))
        let trueUp = simd_cross(right, forward)

        // One focal length for both axes: square pixels, principal point in the
        // middle. A photograph gives no reason to believe anything else.
        let angle = min(max(horizontalFieldOfView, 0.05), 3.0)
        let focal = imageSize.x / 2 / tan(angle / 2)

        return PhotoViewpoint(
            transform: simd_float4x4(SIMD4(right, 0), SIMD4(trueUp, 0),
                                     SIMD4(-forward, 0), SIMD4(eye, 1)),
            intrinsics: simd_float3x3(SIMD3(focal, 0, 0), SIMD3(0, focal, 0),
                                      SIMD3(imageSize.x / 2, imageSize.y / 2, 1)),
            imageResolution: imageSize,
            orientation: .landscapeRight,
            timestamp: 0,
            arkitCheckPixels: nil)
    }

    /// The other way about, so a photo already placed can be picked up and
    /// adjusted rather than started again from a corner.
    static func placing(of viewpoint: PhotoViewpoint, level: Float) -> Placing {
        let spot = viewpoint.planSpot
        return Placing(position: spot.position, yaw: spot.yaw, pitch: spot.pitch,
                       eyeHeight: spot.height - level, level: level,
                       horizontalFieldOfView: spot.fieldOfView)
    }

    /// The upright pixel size of a decoded photo, which is what the intrinsics
    /// are expressed against.
    static func imageSize(of image: UIImage) -> SIMD2<Float> {
        SIMD2(Float(image.size.width * image.scale), Float(image.size.height * image.scale))
    }
}
