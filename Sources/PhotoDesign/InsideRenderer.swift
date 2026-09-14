import SwiftUI
import simd

/// Keeps the interior view on the "Where" step in step with the camera.
///
/// Three things make a drag like this stutter, and all three are avoided here.
/// The renderer is `ShotRenderer.shared`, built once for the app rather than
/// per frame. The render runs on that renderer's own queue, so the gesture
/// never waits for a frame to finish. And a request supersedes the one behind
/// it rather than queueing, so a finger moving faster than the GPU never spends
/// a frame drawing a position it has already left.
@MainActor
final class InsideRenderer: ObservableObject {
    @Published private(set) var image: UIImage?

    /// Small enough to stay ahead of a finger; the sharp frame lands on release.
    static let draftSize = 288
    static let finalSize = 768

    /// How the free camera stands. Mirrors `DesignFlowView.freeCamera`, which
    /// builds the shot that actually gets sent.
    static let eyeHeight: Float = 1.5
    static let pitch: Float = -8 * .pi / 180
    static let fieldOfView: Float = 65 * .pi / 180

    private var mesh: Mesh?
    /// Measured once with the mesh: `bounds` walks every vertex, which is not
    /// something to do on the main thread between frames.
    private var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
    private var isRendering = false
    private var pending: Job?

    private struct Job {
        var position: SIMD2<Float>
        var yaw: Float
        var size: Int
    }

    var isLoaded: Bool { bounds != nil }

    func load(_ mesh: Mesh) {
        guard !mesh.isEmpty else { return }
        self.mesh = mesh
        bounds = mesh.bounds
    }

    func request(position: SIMD2<Float>, yaw: Float, draft: Bool) {
        pending = Job(position: position, yaw: yaw,
                      size: draft ? Self.draftSize : Self.finalSize)
        pump()
    }

    /// Renders the newest request and drops everything queued behind it.
    private func pump() {
        guard !isRendering, let job = pending, let mesh, let bounds else { return }
        pending = nil
        isRendering = true

        Task {
            let camera = Camera.standing(at: job.position, in: bounds,
                                         eyeHeight: Self.eyeHeight, yaw: job.yaw,
                                         pitch: Self.pitch, fieldOfView: Self.fieldOfView)
            // Cropped by the shot itself, so the preview and the render that
            // gets sent frame the same thing.
            let rendered = await ShotRenderer.shared.image(
                of: mesh, shot: PhotoDesignScene.freeShot(camera), size: job.size)
            if let rendered { image = rendered }
            isRendering = false
            pump()
        }
    }
}
