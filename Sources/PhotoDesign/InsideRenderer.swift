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

    private var mesh: Mesh?
    /// Measured once with the mesh: `bounds` walks every vertex, which is not
    /// something to do on the main thread between frames.
    private var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
    private var isRendering = false
    private var pending: Job?

    /// Everything the free camera is, rather than a position and three
    /// constants: the mini screen moves all of it, and the preview has to be
    /// the shot that would be sent.
    private struct Job {
        var position: SIMD2<Float>
        var yaw: Float
        var pitch: Float
        var eyeHeight: Float
        var fieldOfView: Float
        var size: Int
    }

    var isLoaded: Bool { bounds != nil }

    func load(_ mesh: Mesh) {
        guard !mesh.isEmpty else { return }
        self.mesh = mesh
        bounds = mesh.bounds
    }

    func request(position: SIMD2<Float>, yaw: Float, pitch: Float, eyeHeight: Float,
                 fieldOfView: Float, draft: Bool) {
        pending = Job(position: position, yaw: yaw, pitch: pitch, eyeHeight: eyeHeight,
                      fieldOfView: fieldOfView,
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
                                         eyeHeight: job.eyeHeight, yaw: job.yaw,
                                         pitch: job.pitch, fieldOfView: job.fieldOfView)
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
