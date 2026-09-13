import CoreGraphics
import Foundation
import ImageIO
import simd

/// Where the phone stood and how it saw at the instant a scan photo was taken,
/// and every conversion downstream work needs from that. `ScanPhoto` is the
/// front door: `uprightImage`, `viewpoint`, `camera`, `planSpot`.
///
/// Convention: ARKit camera space (+X right, +Y up, looking down −Z) in the
/// sensor's native landscape; the upright image swaps axes when held portrait.
struct PhotoViewpoint: Equatable {
    /// Camera-to-world, in the scan's world space (the AR session's).
    var transform: simd_float4x4
    /// Pixel focal lengths and principal point of the native buffer, as ARKit
    /// gives them: columns (fx, 0, 0), (0, fy, 0), (cx, cy, 1).
    var intrinsics: simd_float3x3
    /// The native buffer's size in pixels; always landscape.
    var imageResolution: SIMD2<Float>
    /// How the screen was held, which decides which way is up in the image.
    var orientation: PhotoOrientation
    /// ARKit's frame timestamp, seconds since boot.
    var timestamp: TimeInterval = 0
    /// Worst gap, in upright pixels, between `pixel(_:)` and ARKit's own
    /// `projectPoint` — measured on the device at capture, not assumed.
    var arkitCheckPixels: Float?
}

/// Named as `UIInterfaceOrientation` names them. ARKit's buffer is always
/// `landscapeRight`: the sensor's own orientation, home side on the right.
enum PhotoOrientation: String, Codable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight

    var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }

    /// What turns the native buffer upright.
    var imageOrientation: CGImagePropertyOrientation {
        switch self {
        case .landscapeRight: return .up
        case .landscapeLeft: return .down
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        }
    }
}

/// A photo seen from above, in `FloorPlan` terms: metres on the (x, z) plane,
/// heading as `Camera.standing` and `CameraPlanPicker` use it.
struct PlanSpot: Equatable {
    var position: SIMD2<Float>
    /// Facing `direction`, i.e. (sin yaw, −cos yaw).
    var yaw: Float
    var pitch: Float
    /// The lens's world y, not its height above the floor.
    var height: Float
    /// Horizontal, for drawing the view cone.
    var fieldOfView: Float

    var direction: SIMD2<Float> { SIMD2(sin(yaw), -cos(yaw)) }
}

extension PhotoViewpoint {

    var eye: SIMD3<Float> { head(transform.columns.3) }
    var forward: SIMD3<Float> { -head(transform.columns.2) }

    /// The world direction that points to the top of the upright image.
    var imageUp: SIMD3<Float> {
        let x = head(transform.columns.0), y = head(transform.columns.1)
        switch orientation {
        case .landscapeRight: return y
        case .landscapeLeft: return -y
        case .portrait: return -x
        case .portraitUpsideDown: return x
        }
    }

    /// The upright image's size in pixels, before any resampling on save.
    var uprightSize: SIMD2<Float> {
        orientation.isPortrait ? SIMD2(imageResolution.y, imageResolution.x) : imageResolution
    }

    var aspect: Float { uprightSize.x / uprightSize.y }

    /// The intrinsics re-expressed for the upright image.
    var uprightIntrinsics: (focal: SIMD2<Float>, principal: SIMD2<Float>) {
        let focal = SIMD2(intrinsics[0][0], intrinsics[1][1])
        let principal = upright(native: SIMD2(intrinsics[2][0], intrinsics[2][1]))
        return (orientation.isPortrait ? SIMD2(focal.y, focal.x) : focal, principal)
    }

    var verticalFieldOfView: Float { 2 * atan(uprightSize.y / 2 / uprightIntrinsics.focal.y) }
    var horizontalFieldOfView: Float { 2 * atan(uprightSize.x / 2 / uprightIntrinsics.focal.x) }

    /// A native-buffer pixel, moved to where it sits in the upright image.
    func upright(native point: SIMD2<Float>) -> SIMD2<Float> {
        let width = imageResolution.x, height = imageResolution.y
        switch orientation {
        case .landscapeRight: return point
        case .landscapeLeft: return SIMD2(width - point.x, height - point.y)
        case .portrait: return SIMD2(height - point.y, point.x)
        case .portraitUpsideDown: return SIMD2(point.y, width - point.x)
        }
    }

    /// Where a world point lands in the upright image, in pixels from the top
    /// left, by the full pinhole model; nil if it is behind the lens.
    func pixel(_ world: SIMD3<Float>) -> SIMD2<Float>? {
        let local = transform.inverse * SIMD4(world, 1)
        let depth = -local.z
        guard depth > 1e-4 else { return nil }
        let native = SIMD2(intrinsics[0][0] * local.x / depth + intrinsics[2][0],
                           intrinsics[2][1] - intrinsics[1][1] * local.y / depth)
        return upright(native: native)
    }

    /// The renderer camera at this viewpoint; render at `aspect` to match the
    /// photo. It centres the principal point, which ARKit has a few pixels off.
    func camera(near: Float = 0.05, far: Float = 40) -> Camera {
        Camera(eye: eye, target: eye + forward, fieldOfView: verticalFieldOfView,
               near: near, far: far, up: imageUp)
    }

    /// For the square-only Metal renderer: a camera whose square covers the
    /// photo, and the part of that square the photo is (0...1, top left).
    func squareCamera(near: Float = 0.05, far: Float = 40) -> (camera: Camera, crop: CGRect) {
        let widest = max(verticalFieldOfView, horizontalFieldOfView)
        var square = camera(near: near, far: far)
        square.fieldOfView = widest
        let span = tan(widest / 2)
        let width = CGFloat(tan(horizontalFieldOfView / 2) / span)
        let height = CGFloat(tan(verticalFieldOfView / 2) / span)
        return (square, CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height))
    }

    var planSpot: PlanSpot {
        // Straight down has no heading of its own; the top of the frame stands in.
        let flat = SIMD2(forward.x, forward.z)
        let heading = simd_length(flat) > 0.1 ? flat : SIMD2(imageUp.x, imageUp.z)
        return PlanSpot(position: SIMD2(eye.x, eye.z),
                        yaw: atan2(heading.x, -heading.y),
                        pitch: asin(min(max(forward.y, -1), 1)),
                        height: eye.y,
                        fieldOfView: horizontalFieldOfView)
    }

    /// The same shot in another world frame, e.g. after a `ScanAlignment`.
    func transformed(by correction: simd_float4x4) -> PhotoViewpoint {
        var moved = self
        moved.transform = correction * transform
        return moved
    }
}

/// Projects world geometry into the upright photo through the renderer
/// `Camera` — the matrices Metal uses — so anything drawn with it tests
/// `camera()` itself. Results run 0...1 from the top left.
struct PhotoProjector {
    let near: Float
    private let view: simd_float4x4
    private let projection: simd_float4x4

    init(_ viewpoint: PhotoViewpoint) {
        let camera = viewpoint.camera()
        near = camera.near
        view = camera.view()
        projection = camera.projection(aspect: viewpoint.aspect)
    }

    func point(_ world: SIMD3<Float>) -> SIMD2<Float>? {
        let local = view * SIMD4(world, 1)
        return local.z < -near ? screen(local) : nil
    }

    /// Clipped at the near plane, so an edge running past the photographer
    /// still draws the part in front.
    func segment(_ start: SIMD3<Float>, _ end: SIMD3<Float>) -> (SIMD2<Float>, SIMD2<Float>)? {
        var a = view * SIMD4(start, 1), b = view * SIMD4(end, 1)
        let plane = -near
        if a.z >= plane && b.z >= plane { return nil }
        if a.z >= plane { a = b + (a - b) * ((plane - b.z) / (a.z - b.z)) }
        if b.z >= plane { b = a + (b - a) * ((plane - a.z) / (b.z - a.z)) }
        return (screen(a), screen(b))
    }

    private func screen(_ local: SIMD4<Float>) -> SIMD2<Float> {
        let clip = projection * local
        return SIMD2((clip.x / clip.w + 1) / 2, (1 - clip.y / clip.w) / 2)
    }
}

// Flat column-major arrays, so the pose reads the same anywhere it is sent.
extension PhotoViewpoint: Codable {
    private enum CodingKeys: String, CodingKey {
        case transform, intrinsics, imageResolution, orientation, timestamp, arkitCheckPixels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let t = try container.decode([Float].self, forKey: .transform)
        let k = try container.decode([Float].self, forKey: .intrinsics)
        guard t.count == 16, k.count == 9 else {
            throw DecodingError.dataCorruptedError(forKey: .transform, in: container,
                                                   debugDescription: "Matrix of the wrong size")
        }
        transform = simd_float4x4(SIMD4(t[0..<4]), SIMD4(t[4..<8]), SIMD4(t[8..<12]), SIMD4(t[12..<16]))
        intrinsics = simd_float3x3(SIMD3(k[0..<3]), SIMD3(k[3..<6]), SIMD3(k[6..<9]))
        imageResolution = try container.decode(SIMD2<Float>.self, forKey: .imageResolution)
        orientation = try container.decode(PhotoOrientation.self, forKey: .orientation)
        timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp) ?? 0
        arkitCheckPixels = try container.decodeIfPresent(Float.self, forKey: .arkitCheckPixels)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode((0..<4).flatMap { c in (0..<4).map { transform[c][$0] } }, forKey: .transform)
        try container.encode((0..<3).flatMap { c in (0..<3).map { intrinsics[c][$0] } }, forKey: .intrinsics)
        try container.encode(imageResolution, forKey: .imageResolution)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(arkitCheckPixels, forKey: .arkitCheckPixels)
    }
}

private func head(_ v: SIMD4<Float>) -> SIMD3<Float> { SIMD3(v.x, v.y, v.z) }
