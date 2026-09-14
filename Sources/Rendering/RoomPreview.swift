import SwiftUI
import simd

/// Keeps the scan screen's render responsive while a finger is moving.
///
/// The walkthrough draws to a drawable, which is right when the only picture is
/// the solid room; this screen also shows depth, lines and normals, which are
/// the offscreen pass's other attachments. So it stays offscreen, on the one
/// `ShotRenderer` pipeline the app already has, and keeps the three things that
/// made dragging smooth: the mesh is built once for the screen's lifetime, the
/// work runs off the main thread, and a position arriving mid-render supersedes
/// whatever was queued behind it rather than joining a queue.
@MainActor
final class RoomPreview: ObservableObject {
    @Published private(set) var image: UIImage?

    /// Small enough to stay ahead of a finger; the full-size frame lands on release.
    static let draftSize = 288
    static let finalSize = 768

    private var mesh: Mesh?
    private var isRendering = false
    private var pending: Job?

    private struct Job {
        var position: SIMD2<Float>
        var yaw: Float
        var pitch: Float
        var eyeHeight: Float
        var fieldOfView: Float
        var kind: ConditioningImages.Kind
        var size: Int
    }

    func load(_ mesh: Mesh) { self.mesh = mesh }

    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? { mesh?.bounds }

    func request(position: SIMD2<Float>, yaw: Float, pitch: Float, eyeHeight: Float,
                 fieldOfView: Float, kind: ConditioningImages.Kind, draft: Bool) {
        pending = Job(position: position, yaw: yaw, pitch: pitch, eyeHeight: eyeHeight,
                      fieldOfView: fieldOfView, kind: kind,
                      size: draft ? Self.draftSize : Self.finalSize)
        pump()
    }

    /// Renders the newest request and drops everything queued behind it — during
    /// a drag only the latest position is worth drawing.
    private func pump() {
        guard !isRendering, let job = pending, let mesh, !mesh.isEmpty else { return }
        pending = nil
        isRendering = true

        Task {
            let camera = Camera.standing(at: job.position, in: mesh.bounds,
                                         eyeHeight: job.eyeHeight, yaw: job.yaw,
                                         pitch: job.pitch, fieldOfView: job.fieldOfView)
            let rendered = await ShotRenderer.shared.image(of: mesh, shot: Self.whole(camera),
                                                           size: job.size, kind: job.kind)
            if let rendered { self.image = rendered }
            self.isRendering = false
            self.pump()
        }
    }

    /// The square as the renderer draws it: the viewfinder shows the whole frame.
    private static func whole(_ camera: Camera) -> Shot {
        Shot(camera: camera, crop: CGRect(x: 0, y: 0, width: 1, height: 1), aspectRatio: "1:1")
    }
}
