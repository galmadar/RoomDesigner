import RoomPlan
import SwiftUI

/// Bridges `RoomCaptureView` into SwiftUI. RoomPlan ships its own scanning UI —
/// the live wireframe, the coaching text — and there is no reason to rebuild it.
struct RoomCaptureViewRepresentable: UIViewRepresentable {
    /// Flipped to true by the caller when the user taps Done.
    let isFinished: Bool
    let onFinish: (Result<CapturedRoom, Error>) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        guard isFinished else { return }
        context.coordinator.stop()
    }

    func makeCoordinator() -> RoomCaptureCoordinator {
        RoomCaptureCoordinator(onFinish: onFinish)
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        coordinator.stop()
    }
}

/// Deliberately not nested inside the representable: `RoomCaptureViewDelegate`
/// inherits `NSCoding`, and a nested type has no stable Objective-C name to
/// archive under, so the compiler refuses it.
final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate {
    weak var view: RoomCaptureView?

    private let onFinish: (Result<CapturedRoom, Error>) -> Void
    private var hasStopped = false
    private var hasReported = false

    init(onFinish: @escaping (Result<CapturedRoom, Error>) -> Void) {
        self.onFinish = onFinish
        super.init()
    }

    /// `NSCoding` is only here because the delegate protocol demands it. A live
    /// capture coordinator is not something anyone archives.
    required init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {}

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        view?.captureSession.stop()
    }

    /// Returning true lets RoomPlan run its post-processing pass, which is what
    /// turns a live scan into clean parametric surfaces.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                     error: Error?) -> Bool {
        if let error { report(.failure(error)); return false }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error { report(.failure(error)) } else { report(.success(processedResult)) }
    }

    private func report(_ result: Result<CapturedRoom, Error>) {
        guard !hasReported else { return }
        hasReported = true
        onFinish(result)
    }
}
