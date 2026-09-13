import SwiftUI

/// Make a picture of what you are looking at, without leaving the room.
///
/// The Camera app's shutter — white ring, white disc, giving under the thumb —
/// because that is the one control everybody already reads as "take this, now".
/// The glyph inside is the app's own mark for designing rather than a lens, so
/// it promises a picture made of this view instead of a photograph of a screen.
struct WalkShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4)
                Circle().fill(.white).padding(8)
                Image(systemName: "sparkles")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .frame(width: 68, height: 68)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        }
        .buttonStyle(ShutterPressStyle())
        .accessibilityLabel("Make a picture from here")
        .accessibilityHint("Designs the room from exactly this view")
    }
}
