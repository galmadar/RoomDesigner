import SwiftUI
import simd

/// Keeps the viewpoint preview responsive while a finger is moving.
///
/// Three things were making the drag stutter, all of them fixable:
/// the renderer was rebuilt per frame (pipeline compilation and all), the work
/// ran on the main thread so the gesture could not advance until a frame
/// finished, and every drag position queued its own render rather than
/// superseding the last.
@MainActor
final class PreviewRenderer: ObservableObject {
    @Published private(set) var image: UIImage?

    private let renderer: Renderer?
    private let queue = DispatchQueue(label: "room.preview", qos: .userInteractive)

    private var mesh: Mesh?
    private var isRendering = false
    private var pending: Job?

    private struct Job: Equatable {
        var position: SIMD2<Float>
        var yaw: Float
        var kind: ConditioningImages.Kind
        var size: Int
    }

    /// Small enough to stay ahead of a finger; the full-size frame lands on release.
    static let draftSize = 288
    static let finalSize = 768

    init() { renderer = try? Renderer() }

    func load(_ mesh: Mesh) { self.mesh = mesh }

    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? { mesh?.bounds }

    func request(position: SIMD2<Float>, yaw: Float,
                 kind: ConditioningImages.Kind, draft: Bool) {
        pending = Job(position: position, yaw: yaw, kind: kind,
                      size: draft ? Self.draftSize : Self.finalSize)
        pump()
    }

    /// Renders the newest request and drops everything queued behind it — during
    /// a drag only the latest position is worth drawing.
    private func pump() {
        guard !isRendering, let job = pending, let renderer, let mesh, !mesh.isEmpty
        else { return }
        pending = nil
        isRendering = true

        queue.async {
            let camera = Camera.standing(at: job.position, in: mesh.bounds, yaw: job.yaw)
            let rendered = (try? renderer.render(mesh, camera: camera, size: job.size))
                .flatMap { ConditioningImages.image(job.kind, from: $0) }

            Task { @MainActor in
                if let rendered { self.image = rendered }
                self.isRendering = false
                self.pump()
            }
        }
    }
}
