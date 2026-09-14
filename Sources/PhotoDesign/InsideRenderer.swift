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

    /// The shot itself rather than a camera's ingredients: the free camera is
    /// one way of arriving at one, and a photo being placed is another, and
    /// both want the same supersede-don't-queue behaviour underneath.
    private struct Job {
        var shot: Shot
        var size: Int
    }

    var isLoaded: Bool { bounds != nil }

    /// The measured extent of the loaded mesh, for callers that place their own
    /// camera in it rather than handing in a spot to be clamped.
    var measured: (min: SIMD3<Float>, max: SIMD3<Float>)? { bounds }

    func load(_ mesh: Mesh) {
        guard !mesh.isEmpty else { return }
        self.mesh = mesh
        bounds = mesh.bounds
    }

    func request(position: SIMD2<Float>, yaw: Float, pitch: Float, eyeHeight: Float,
                 fieldOfView: Float, draft: Bool) {
        guard let bounds else { return }
        let camera = Camera.standing(at: position, in: bounds, eyeHeight: eyeHeight,
                                     yaw: yaw, pitch: pitch, fieldOfView: fieldOfView)
        // Cropped by the shot itself, so the preview and the render that gets
        // sent frame the same thing.
        request(PhotoDesignScene.freeShot(camera), draft: draft)
    }

    /// A shot built elsewhere — a photo's own camera and crop — so the render
    /// covers exactly what the photograph covers and the two can be crossed.
    func request(_ shot: Shot, draft: Bool) {
        pending = Job(shot: shot, size: draft ? Self.draftSize : Self.finalSize)
        pump()
    }

    /// Renders the newest request and drops everything queued behind it.
    private func pump() {
        guard !isRendering, let job = pending, let mesh else { return }
        pending = nil
        isRendering = true

        Task {
            let rendered = await ShotRenderer.shared.image(of: mesh, shot: job.shot,
                                                           size: job.size)
            if let rendered { image = rendered }
            isRendering = false
            pump()
        }
    }
}
