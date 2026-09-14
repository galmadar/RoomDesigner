import RoomPlan
import SwiftUI

/// Full-screen scanning, in the three moments the scan is actually made of:
/// the plan of the walk, the walk itself, and an honest verdict on what came
/// out — offered before any time has been spent on the room.
struct ScanFlowView: View {
    /// Everything one scan produced, handed over whole so the caller can build the room in one place.
    struct Result {
        let room: CapturedRoom
        let shots: [ScanCamera.Shot]
        let liveRoomData: Data?
        /// The session's archived `ARWorldMap`, or nil if it had none to give.
        /// Kept so a photo added to this room later can be placed by standing in
        /// it again rather than by eye — see ``RoomWorldMap``.
        let worldMapData: Data?
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var learned = Learned.shared

    let onCaptured: (Result) -> Void

    private enum Phase: Equatable {
        case ready
        case scanning
        case finished
    }

    @State private var phase: Phase
    /// Bumped by "Scan it again", which throws the whole capture away — session,
    /// camera, coach and photos — rather than trying to reuse a finished one.
    @State private var attempt = 0
    @State private var result: Result?
    @State private var failure: String?

    init(onCaptured: @escaping (Result) -> Void) {
        self.onCaptured = onCaptured
        // Shown once, and re-openable afterwards from "How this works".
        _phase = State(initialValue: Learned.shared.hasSeen(.beforeScan) ? .scanning : .ready)
    }

    var body: some View {
        ZStack {
            if !RoomCaptureSession.isSupported {
                unsupported
            } else {
                switch phase {
                case .ready:
                    LearnScanReadyView(onStart: start, onCancel: { dismiss() })
                case .scanning:
                    ScanCaptureStage(onFinished: finished, onCancel: { dismiss() },
                                     onFailure: { failure = $0 })
                        .id(attempt)
                case .finished:
                    if let result {
                        LearnScanDoneView(
                            verdict: ScanVerdict(room: result.room),
                            room: result.room,
                            photos: result.shots.compactMap {
                                ($0.thumbnail ?? $0.jpeg).flatMap(UIImage.init(data:))
                            },
                            onScanAgain: scanAgain, onKeep: keep)
                    }
                }
            }
        }
        .alert("Scan failed", isPresented: .constant(failure != nil)) {
            Button("OK") { failure = nil; dismiss() }
        } message: {
            Text(failure ?? "")
        }
    }

    private func start() {
        learned.mark(.beforeScan)
        phase = .scanning
    }

    private func finished(_ made: Result) {
        result = made
        phase = .finished
    }

    /// Nothing is saved until "Keep this room", so going again costs only the walk.
    private func scanAgain() {
        result = nil
        attempt += 1
        phase = .scanning
    }

    private func keep() {
        guard let result else { return }
        onCaptured(result)
        dismiss()
    }

    private var unsupported: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Paper.mutedInk)
                Text("No LiDAR scanner")
                    .question()
                    .multilineTextAlignment(.center)
                Text("Room scanning needs a device with a LiDAR scanner — a Pro iPhone or an iPad Pro.")
                    .font(.system(size: 14))
                    .foregroundStyle(Paper.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                Button("Close") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
            }
        }
    }
}

/// The walk itself. Owns the capture session, the photo camera and the coach,
/// so a second attempt gets brand new ones rather than a reset of the old.
private struct ScanCaptureStage: View {
    let onFinished: (ScanFlowView.Result) -> Void
    let onCancel: () -> Void
    let onFailure: (String) -> Void

    @StateObject private var camera = ScanCamera()
    @StateObject private var coach = ScanCoach()
    @State private var isFinishing = false
    /// True for the moment between the tap and the capture being stopped, while
    /// the room's world map is being taken.
    @State private var isKeepingMap = false
    @State private var worldMapData: Data?

    var body: some View {
        ZStack {
            RoomCaptureViewRepresentable(isFinished: isFinishing, camera: camera, coach: coach) { result in
                switch result {
                case .success(let room):
                    Task { @MainActor in await finish(with: room) }
                case .failure(let error):
                    onFailure(error.localizedDescription)
                }
            }
            .ignoresSafeArea()

            flash

            ScanCoachOverlay(coach: coach, photoCount: camera.count,
                             isFinishing: isFinishing || isKeepingMap,
                             onCancel: onCancel, onShutter: { camera.capture() },
                             onFinish: { wrapUp() })
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: camera.count)
        .sensoryFeedback(.warning, trigger: camera.misses)
    }

    /// A white blink over the camera feed, like a shutter firing.
    private var flash: some View {
        Color.white
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .keyframeAnimator(initialValue: 0.0, trigger: camera.count) { content, opacity in
                content.opacity(opacity)
            } keyframes: { _ in
                LinearKeyframe(0.7, duration: 0.04)
                CubicKeyframe(0, duration: 0.25)
            }
    }

    /// The room's map is taken here, on the tap, and not after: stopping the
    /// capture pauses the AR session underneath it, and the map only exists
    /// while that session runs. A scan that yields none simply has none — the
    /// capture is stopped either way, so this can only cost a moment.
    private func wrapUp() {
        guard !isFinishing, !isKeepingMap else { return }
        isKeepingMap = true
        Task {
            worldMapData = await camera.worldMapData()
            isKeepingMap = false
            isFinishing = true
        }
    }

    private func finish(with captured: CapturedRoom) async {
        let shots = await camera.collected()
        onFinished(.init(room: captured, shots: shots, liveRoomData: camera.liveRoomData,
                         worldMapData: worldMapData))
    }
}
