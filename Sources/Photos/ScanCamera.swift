import ARKit
import CoreImage
import ImageIO
import RoomPlan
import UIKit

/// Takes photos from RoomPlan's own AR session while it scans, so each pose is
/// in the world frame the room is built in.
@MainActor
final class ScanCamera: ObservableObject {
    struct Shot {
        let takenAt: Date
        let jpeg: Data
        let thumbnail: Data?
        let viewpoint: PhotoViewpoint
    }

    @Published private(set) var count = 0
    /// Bumped when the shutter found no frame to take, so the view can buzz.
    @Published private(set) var misses = 0

    private weak var view: RoomCaptureView?
    private let liveRoom = LiveRoomRecorder()
    private var encoding: [Task<Shot?, Never>] = []

    func attach(to view: RoomCaptureView) {
        self.view = view
        liveRoom.install(on: view.captureSession)
    }

    func capture() {
        guard let view, let taken = Self.take(from: view) else { misses += 1; return }
        count += 1
        let takenAt = Date.now
        encoding.append(Task.detached(priority: .userInitiated) {
            PhotoEncoder.encode(taken.pixels, orientation: taken.viewpoint.orientation.imageOrientation)
                .map { Shot(takenAt: takenAt, jpeg: $0.jpeg, thumbnail: $0.thumbnail,
                            viewpoint: taken.viewpoint) }
        })
    }

    /// Waits for any photo still being encoded.
    func collected() async -> [Shot] {
        var shots: [Shot] = []
        for task in encoding {
            if let shot = await task.value { shots.append(shot) }
        }
        return shots
    }

    var liveRoomData: Data? { liveRoom.latest.flatMap { try? JSONEncoder().encode($0) } }

    /// Everything is copied out before this returns: ARKit stops delivering
    /// frames while old ones are still held.
    private static func take(from view: RoomCaptureView)
        -> (pixels: CVPixelBuffer, viewpoint: PhotoViewpoint)? {
        guard let frame = view.captureSession.arSession.currentFrame,
              let pixels = PixelCopy.copy(frame.capturedImage) else { return nil }
        var held = view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        if held == .unknown { held = .portrait }

        let camera = frame.camera
        var viewpoint = PhotoViewpoint(
            transform: camera.transform,
            intrinsics: camera.intrinsics,
            imageResolution: SIMD2(Float(camera.imageResolution.width),
                                   Float(camera.imageResolution.height)),
            orientation: PhotoOrientation(held),
            timestamp: frame.timestamp)
        viewpoint.arkitCheckPixels = check(viewpoint, against: camera, held: held)
        return (pixels, viewpoint)
    }

    /// Our projection against ARKit's own, at a few points in front of the lens.
    private static func check(_ viewpoint: PhotoViewpoint, against camera: ARCamera,
                              held: UIInterfaceOrientation) -> Float? {
        let size = CGSize(width: CGFloat(viewpoint.uprightSize.x),
                          height: CGFloat(viewpoint.uprightSize.y))
        let probes: [SIMD3<Float>] = [SIMD3(0, 0, -2), SIMD3(0.6, 0.4, -2), SIMD3(-0.5, -0.7, -1.5)]
        var worst: Float = 0
        for probe in probes {
            let world = (viewpoint.transform * SIMD4(probe, 1)).xyz
            guard let ours = viewpoint.pixel(world) else { return nil }
            let theirs = camera.projectPoint(world, orientation: held, viewportSize: size)
            worst = max(worst, simd_distance(ours, SIMD2(Float(theirs.x), Float(theirs.y))))
        }
        return worst
    }
}

extension PhotoOrientation {
    init(_ interface: UIInterfaceOrientation) {
        switch interface {
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: self = .portrait
        }
    }
}

/// Keeps the newest live room while passing every callback on to whoever held
/// the session's delegate before, so RoomCaptureView's own UI is untouched.
final class LiveRoomRecorder: RoomCaptureSessionDelegate {
    private weak var previous: (any RoomCaptureSessionDelegate)?
    private let lock = NSLock()
    private var room: CapturedRoom?

    var latest: CapturedRoom? { lock.withLock { room } }

    func install(on session: RoomCaptureSession) {
        guard session.delegate !== self else { return }
        previous = session.delegate
        session.delegate = self
    }

    private func keep(_ room: CapturedRoom) { lock.withLock { self.room = room } }

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        keep(room)
        previous?.captureSession(session, didUpdate: room)
    }

    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
        keep(room)
        previous?.captureSession(session, didAdd: room)
    }

    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
        keep(room)
        previous?.captureSession(session, didChange: room)
    }

    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {
        previous?.captureSession(session, didRemove: room)
    }

    func captureSession(_ session: RoomCaptureSession,
                        didProvide instruction: RoomCaptureSession.Instruction) {
        previous?.captureSession(session, didProvide: instruction)
    }

    func captureSession(_ session: RoomCaptureSession,
                        didStartWith configuration: RoomCaptureSession.Configuration) {
        previous?.captureSession(session, didStartWith: configuration)
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData,
                        error: Error?) {
        previous?.captureSession(session, didEndWith: data, error: error)
    }
}

/// A private copy of a camera buffer, so ARKit's own goes straight back to its pool.
enum PixelCopy {
    static func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        guard CVPixelBufferCreate(nil, CVPixelBufferGetWidth(source), CVPixelBufferGetHeight(source),
                                  CVPixelBufferGetPixelFormatType(source), attributes,
                                  &made) == kCVReturnSuccess,
              let copy = made else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        let planar = CVPixelBufferIsPlanar(source)
        for plane in 0..<max(CVPixelBufferGetPlaneCount(source), 1) {
            guard let from = planar ? CVPixelBufferGetBaseAddressOfPlane(source, plane)
                                    : CVPixelBufferGetBaseAddress(source),
                  let to = planar ? CVPixelBufferGetBaseAddressOfPlane(copy, plane)
                                  : CVPixelBufferGetBaseAddress(copy) else { return nil }
            let rows = planar ? CVPixelBufferGetHeightOfPlane(source, plane)
                              : CVPixelBufferGetHeight(source)
            let fromStride = planar ? CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                                    : CVPixelBufferGetBytesPerRow(source)
            let toStride = planar ? CVPixelBufferGetBytesPerRowOfPlane(copy, plane)
                                  : CVPixelBufferGetBytesPerRow(copy)
            for row in 0..<rows {
                memcpy(to + row * toStride, from + row * fromStride, min(fromStride, toStride))
            }
        }
        // Carries the colour tags CoreImage reads to convert YCbCr correctly.
        CVBufferPropagateAttachments(source, copy)
        return copy
    }
}

/// The pixel work, kept off the main thread.
enum PhotoEncoder {
    /// Shared: a CIContext is costly to make and safe to use from any thread.
    private static let context = CIContext()
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func encode(_ pixels: CVPixelBuffer,
                       orientation: CGImagePropertyOrientation) -> (jpeg: Data, thumbnail: Data?)? {
        let upright = CIImage(cvPixelBuffer: pixels).oriented(orientation)
        let longEdge = max(upright.extent.width, upright.extent.height)
        guard longEdge > 0 else { return nil }
        // The floor an image model is fed at; ARKit's feed is usually exactly this.
        let full = longEdge < 1920 ? scaled(upright, by: 1920 / longEdge) : upright
        guard let jpeg = encodeJPEG(full, quality: 0.85) else { return nil }
        return (jpeg, encodeJPEG(scaled(upright, by: 320 / longEdge), quality: 0.7))
    }

    private static func scaled(_ image: CIImage, by factor: CGFloat) -> CIImage {
        image.transformed(by: CGAffineTransform(scaleX: factor, y: factor), highQualityDownsample: true)
    }

    private static func encodeJPEG(_ image: CIImage, quality: CGFloat) -> Data? {
        context.jpegRepresentation(
            of: image, colorSpace: sRGB,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }
}
