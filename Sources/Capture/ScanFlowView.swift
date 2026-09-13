import RoomPlan
import SwiftUI

/// Full-screen scanning: walk the room, take photos along the way, tap Done,
/// get a `CapturedRoom` back along with the photos.
struct ScanFlowView: View {
    /// Everything one scan produced, handed over whole so the caller can build the room in one place.
    struct Result {
        let room: CapturedRoom
        let shots: [ScanCamera.Shot]
        let liveRoomData: Data?
    }

    @Environment(\.dismiss) private var dismiss

    let onCaptured: (Result) -> Void

    @StateObject private var camera = ScanCamera()
    @State private var isFinished = false
    @State private var failure: String?

    var body: some View {
        ZStack {
            if RoomCaptureSession.isSupported {
                RoomCaptureViewRepresentable(isFinished: isFinished, camera: camera) { result in
                    switch result {
                    case .success(let room):
                        Task { @MainActor in await finish(with: room) }
                    case .failure(let error):
                        failure = error.localizedDescription
                    }
                }
                .ignoresSafeArea()
            } else {
                unsupported
            }

            flash

            VStack {
                Spacer()
                if RoomCaptureSession.isSupported {
                    ZStack {
                        Button(isFinished ? "Finishing…" : "Done") { isFinished = true }
                            .buttonStyle(CameraChipStyle())
                            .disabled(isFinished)
                        // A bottom corner: under the thumb, and clear of RoomPlan's
                        // coaching, which sits mid-screen.
                        if !isFinished {
                            ShutterButton(count: camera.count) { camera.capture() }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 24)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: camera.count)
        .sensoryFeedback(.warning, trigger: camera.misses)
        .overlay(alignment: .topTrailing) {
            Button("Cancel") { dismiss() }
                .buttonStyle(CameraChipStyle())
                .padding(16)
        }
        .alert("Scan failed", isPresented: .constant(failure != nil)) {
            Button("OK") { failure = nil; dismiss() }
        } message: {
            Text(failure ?? "")
        }
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

    private func finish(with captured: CapturedRoom) async {
        let shots = await camera.collected()
        onCaptured(Result(room: captured, shots: shots, liveRoomData: camera.liveRoomData))
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
            }
        }
    }
}

/// Our controls over RoomPlan's own camera view: the design's card, raised off a
/// moving picture rather than tinted into it.
private struct CameraChipStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Paper.ink)
            .padding(.horizontal, 22)
            .frame(minHeight: 48)
            .background(Paper.card, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}
