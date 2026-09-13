import CoreGraphics
import UIKit

/// A camera plus the part of its square render that makes the picture.
struct Shot {
    var camera: Camera
    /// 0...1 from the top left of the square.
    var crop: CGRect
    /// As the compose endpoint names it: "4:3" or "3:4".
    var aspectRatio: String
}

/// Renders the room through any camera and crops it to any aspect, since
/// `Renderer` only draws squares. `PreviewRenderer` stays the free camera's.
final class ShotRenderer: @unchecked Sendable {
    /// One Metal pipeline for every screen that needs an exact shot; the queue serialises it.
    static let shared = ShotRenderer()

    private let renderer: Renderer?
    private let queue = DispatchQueue(label: "room.shot", qos: .userInitiated)

    private init() { renderer = try? Renderer() }

    func image(of mesh: Mesh, shot: Shot, size: Int,
               kind: ConditioningImages.Kind = .room) async -> UIImage? {
        guard let renderer, !mesh.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                let square = (try? renderer.render(mesh, camera: shot.camera, size: size))
                    .flatMap { ConditioningImages.image(kind, from: $0) }?.cgImage
                let side = CGFloat(size)
                let pixels = CGRect(x: shot.crop.minX * side, y: shot.crop.minY * side,
                                    width: shot.crop.width * side, height: shot.crop.height * side)
                    .integral
                continuation.resume(returning: square?.cropping(to: pixels).map { UIImage(cgImage: $0) })
            }
        }
    }
}
