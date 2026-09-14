import SwiftUI

/// The Camera app's shutter — white ring, white disc — with a camera glyph so
/// there is no doubt left about what it does.
struct ShutterButton: View {
    let count: Int
    let action: () -> Void

    @Environment(\.roomAccent) private var accent

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 5)
                Circle().fill(.white).padding(9)
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .frame(width: 80, height: 80)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(accent, in: Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(ShutterPressStyle())
        .accessibilityLabel("Take photo")
        .accessibilityValue(Text("^[\(count) photo](inflect: true) taken"))
    }
}

/// Gives under the thumb, the way a physical shutter does.
struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
