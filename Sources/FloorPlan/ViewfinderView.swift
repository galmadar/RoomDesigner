import SwiftUI

/// The conditioning render, made draggable.
///
/// Reaching for the floor plan to change what you are looking at is indirect —
/// you aim by watching a wedge rather than by watching the picture. Dragging on
/// the picture itself is how every viewfinder works: side to side turns, up and
/// down tilts.
struct ViewfinderView: View {
    let image: UIImage?

    @Binding var yaw: Float
    @Binding var pitch: Float
    @Binding var isDragging: Bool

    /// Roughly a quarter turn across the width of the view.
    private let turnPerPoint: Float = .pi / 2 / 340
    private let tiltLimit: Float = 40 * .pi / 180

    @State private var anchor: (yaw: Float, pitch: Float)?
    @State private var showsHint = true

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 200)
                    .overlay(ProgressView())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = anchor ?? (yaw, pitch)
                    if anchor == nil {
                        anchor = start
                        showsHint = false
                    }
                    isDragging = true
                    yaw = start.yaw + Float(value.translation.width) * turnPerPoint
                    pitch = min(max(start.pitch - Float(value.translation.height) * turnPerPoint,
                                    -tiltLimit), tiltLimit)
                }
                .onEnded { _ in
                    anchor = nil
                    isDragging = false
                }
        )
        .overlay(alignment: .bottom) {
            if showsHint && image != nil {
                Label("Drag to look around", systemImage: "hand.draw")
                    .font(.caption2)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if abs(pitch) > 0.01 {
                Text(pitch > 0 ? "looking up \(degrees)°" : "looking down \(degrees)°")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }
        }
    }

    private var degrees: Int { abs(Int(pitch * 180 / .pi)) }
}
