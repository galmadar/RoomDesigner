import RoomPlan
import SwiftData
import SwiftUI

/// Full-screen scanning: walk the room, take photos along the way, tap Done,
/// get a `CapturedRoom` back with the photos hung on it.
struct ScanFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let onCaptured: (CapturedRoom) -> Void

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
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
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
                .padding()
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

    /// The caller creates the room, so it is found afterwards as the one that
    /// is new — which leaves the caller's side of this untouched.
    private func finish(with captured: CapturedRoom) async {
        let shots = await camera.collected()
        let before = Set(rooms().map(\.persistentModelID))
        onCaptured(captured)

        let created = rooms().filter { !before.contains($0.persistentModelID) }
        if created.count == 1, let room = created.first {
            room.liveRoomData = camera.liveRoomData
            for shot in shots {
                let photo = ScanPhoto(takenAt: shot.takenAt, imageData: shot.jpeg,
                                      thumbnailData: shot.thumbnail, viewpoint: shot.viewpoint)
                context.insert(photo)
                photo.room = room
            }
        }
        dismiss()
    }

    private func rooms() -> [ScannedRoom] {
        (try? context.fetch(FetchDescriptor<ScannedRoom>())) ?? []
    }

    private var unsupported: some View {
        ContentUnavailableView {
            Label("No LiDAR scanner", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Room scanning needs a device with a LiDAR scanner — a Pro iPhone or an iPad Pro.")
        }
    }
}
