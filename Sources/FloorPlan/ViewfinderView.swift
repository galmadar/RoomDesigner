import SwiftUI

/// The render of the scan, made draggable.
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
            Paper.tint
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(Paper.mutedInk)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                badge { Label("Drag to look around", systemImage: "hand.draw") }
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if abs(pitch) > 0.01 {
                badge {
                    Text(pitch > 0 ? "looking up \(degrees)°" : "looking down \(degrees)°")
                        .monospacedDigit()
                }
                .padding(10)
            }
        }
        .accessibilityLabel("The scan seen from where you are standing. Drag to look around.")
    }

    private func badge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.system(size: 12))
            .foregroundStyle(Paper.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Paper.card.opacity(0.92), in: Capsule())
    }

    private var degrees: Int { abs(Int(pitch * 180 / .pi)) }
}
