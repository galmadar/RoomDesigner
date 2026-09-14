import ARKit
import CoreImage
import SwiftData
import SwiftUI
import simd

/// Placing a photo by going and standing where it was taken.
///
/// This is the only path that ends in a measured position rather than a judged
/// one. The app hands ARKit the world map kept from the scan, ARKit relocalises
/// against it, and from then on every camera pose it reports is in the same
/// frame the walls were measured in — so reading the pose off the phone puts
/// the photo exactly where the phone is. Nothing is lined up by eye.
///
/// **None of this has been run.** Relocalisation needs a LiDAR-scanned room and
/// a saved world map, and a simulator has neither, so it is built to fail
/// safely rather than proved to work: it owns its own `ARSession` and never
/// touches RoomPlan's, it refuses to start without a map, it pauses on the way
/// out, and its one button is live only while ARKit reports normal tracking —
/// which, with an initial world map set, it does not report until it has
/// localised against that map.
struct PhotoStandInRoomView: View {
    let room: ScannedRoom
    let photo: ScanPhoto
    let onFinished: () -> Void

    @Environment(\.modelContext) private var context

    @StateObject private var session = RelocaliseSession()
    @State private var photograph: UIImage?
    @State private var blend: Double = 0.45

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ZStack {
                if let feed = session.feed {
                    Image(uiImage: feed).resizable().scaledToFill()
                }
                if let photograph {
                    Image(uiImage: photograph)
                        .resizable()
                        .scaledToFit()
                        .opacity(blend)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()

            chrome
        }
        .navigationTitle("Stand where you took it")
        .navigationBarTitleDisplayMode(.inline)
        .task { await open() }
        .onDisappear { session.stop() }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Text(session.state.saying)
                    .font(.system(size: 14))
                    .foregroundStyle(Paper.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text("Camera").font(.system(size: 13)).foregroundStyle(Paper.secondaryInk)
                    Slider(value: $blend, in: 0...1)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Blend between the live camera and the photograph")
                    Text("Photo").font(.system(size: 13)).foregroundStyle(Paper.secondaryInk)
                }

                Button("This is where I stood", action: keep)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!session.state.isReady)
            }
            .padding(16)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func open() async {
        let data = photo.imageData
        photograph = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
        await session.start(mapData: room.worldMapData)
    }

    /// The pose comes from ARKit whole; only the lens is ours, and it is the
    /// live lens's own angle across the frame as it is being held — which is
    /// the angle the photograph has just been matched against.
    private func keep() {
        guard let fix = session.fix(), let photograph,
              let placed = PhotoPose.viewpoint(
                eye: fix.eye, forward: fix.forward,
                imageSize: PhotoPose.imageSize(of: photograph),
                horizontalFieldOfView: fix.horizontalFieldOfView)
        else { return }
        photo.place(placed, by: .relocalised)
        try? context.save()
        session.stop()
        onFinished()
    }
}

/// An `ARSession` reopened in the room's own coordinates.
///
/// Entirely separate from RoomPlan's session, which it must never touch: this
/// screen is only ever reached from a room that has already been scanned, so
/// there is no capture in flight, and its own session is paused the moment the
/// screen goes away.
@MainActor
final class RelocaliseSession: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        /// Nothing can be done here, and why.
        case impossible(String)
        /// Running, but ARKit has not found where it is yet.
        case finding(String)
        /// Localised against the scan's map: a pose read now means something.
        case ready
        case lost(String)

        var isReady: Bool { self == .ready }

        var saying: String {
            switch self {
            case .idle: return "Starting the camera…"
            case .impossible(let why): return why
            case .finding(let how): return how
            case .ready:
                return "Found the room. Line the live camera up with the photograph, then tap."
            case .lost(let why): return why
            }
        }
    }

    /// What a placed photo needs from the live camera.
    struct Fix {
        var eye: SIMD3<Float>
        var forward: SIMD3<Float>
        /// Across the frame as the phone is being held.
        var horizontalFieldOfView: Float
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var feed: UIImage?

    private let session = ARSession()
    private let context = CIContext()
    private var isConverting = false
    private var isRunning = false

    func start(mapData: Data?) async {
        guard !isRunning else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            return state = .impossible("This device can't run the tracking this needs.")
        }
        guard let mapData else {
            return state = .impossible("This room has no saved map, so there is no way to put you back in its coordinates.")
        }

        state = .finding("Loading the room's map…")
        // Megabytes of feature points; never unarchived on the main thread.
        let map = await Task.detached(priority: .userInitiated) {
            RoomWorldMap.unarchived(mapData)
        }.value
        guard let map else {
            return state = .impossible("The room's saved map couldn't be read.")
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.initialWorldMap = map
        configuration.planeDetection = []
        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        state = .finding("Point the camera at what you scanned. ARKit is looking for where it is.")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        session.delegate = nil
        session.pause()
    }

    func fix() -> Fix? {
        guard state.isReady, let frame = session.currentFrame else { return nil }
        let camera = frame.camera
        let transform = camera.transform
        let eye = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let forward = SIMD3(-transform.columns.2.x, -transform.columns.2.y,
                            -transform.columns.2.z)

        // Read through `PhotoViewpoint` rather than by hand, so the angle is the
        // one every other screen would work out from the same frame.
        let live = PhotoViewpoint(
            transform: transform, intrinsics: camera.intrinsics,
            imageResolution: SIMD2(Float(camera.imageResolution.width),
                                   Float(camera.imageResolution.height)),
            orientation: Self.held())
        return Fix(eye: eye, forward: forward,
                   horizontalFieldOfView: live.horizontalFieldOfView)
    }

    fileprivate static func held() -> PhotoOrientation {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        var held = scene?.effectiveGeometry.interfaceOrientation ?? .portrait
        if held == .unknown { held = .portrait }
        return PhotoOrientation(held)
    }

    fileprivate func absorb(_ tracking: ARCamera.TrackingState) {
        switch tracking {
        case .normal:
            if state != .ready { state = .ready }
        case .notAvailable:
            state = .finding("Starting up…")
        case .limited(let reason):
            state = .finding(RelocaliseFeed.saying(reason))
        }
    }

    /// Drops frames rather than queueing them: only the newest is worth drawing,
    /// and the conversion is slower than ARKit's delivery.
    fileprivate func show(_ buffer: CVPixelBuffer?) {
        guard let buffer, !isConverting else { return }
        isConverting = true
        let orientation = Self.held().imageOrientation
        let context = self.context
        Task.detached(priority: .userInitiated) {
            let image = RelocaliseFeed.picture(buffer, orientation: orientation,
                                               context: context)
            await MainActor.run { [weak self] in
                if let image { self?.feed = image }
                self?.isConverting = false
            }
        }
    }

    fileprivate func fail(_ message: String) { state = .lost(message) }

    fileprivate func interrupted() {
        state = .finding("The camera was interrupted. Point it at the room again.")
    }
}

extension RelocaliseSession: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Everything is read out here: ARKit stops delivering frames while old
        // ones are still held.
        let copy = PixelCopy.copy(frame.capturedImage)
        let tracking = frame.camera.trackingState
        Task { @MainActor [weak self] in
            self?.absorb(tracking)
            self?.show(copy)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.fail(message) }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in self?.interrupted() }
    }
}

/// The pixel and vocabulary work, off the main actor.
private enum RelocaliseFeed {
    /// Small: this is a viewfinder, not a photograph. Converting a full buffer
    /// sixty times a second is how this screen would cook a phone.
    static let edge: CGFloat = 720

    static func saying(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .relocalizing:
            return "Looking for where you are. Point the camera at walls and furniture the scan covered."
        case .initializing:
            return "Starting up…"
        case .excessiveMotion:
            return "Too much movement — hold the phone steadier."
        case .insufficientFeatures:
            return "Not enough to go on here. Try a wall with more on it."
        @unknown default:
            return "Looking for where you are."
        }
    }

    static func picture(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                        context: CIContext) -> UIImage? {
        let upright = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let longEdge = max(upright.extent.width, upright.extent.height)
        guard longEdge > 0 else { return nil }
        let factor = min(edge / longEdge, 1)
        let scaled = upright.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
