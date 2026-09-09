import RoomPlan
import SwiftUI

/// Full-screen scanning: walk the room, tap Done, get a `CapturedRoom` back.
struct ScanFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let onCaptured: (CapturedRoom) -> Void

    @State private var isFinished = false
    @State private var failure: String?

    var body: some View {
        ZStack {
            if RoomCaptureSession.isSupported {
                RoomCaptureViewRepresentable(isFinished: isFinished) { result in
                    switch result {
                    case .success(let room):
                        onCaptured(room)
                        dismiss()
                    case .failure(let error):
                        failure = error.localizedDescription
                    }
                }
                .ignoresSafeArea()
            } else {
                unsupported
            }

            VStack {
                Spacer()
                if RoomCaptureSession.isSupported {
                    Button(isFinished ? "Finishing…" : "Done") { isFinished = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isFinished)
                        .padding(.bottom, 32)
                }
            }
        }
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

    private var unsupported: some View {
        ContentUnavailableView {
            Label("No LiDAR scanner", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Room scanning needs a device with a LiDAR scanner — a Pro iPhone or an iPad Pro.")
        }
    }
}
