import SwiftUI

/// The one screen shown before anything has been earned.
///
/// It exists because the next thing asked of the person is physical — walk
/// around your flat for two minutes — and that has to be agreed to before it
/// happens. So: what comes out, what it costs, one button.
struct LearnFirstView: View {
    let onScan: () -> Void

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            VStack(spacing: 0) {
                Color.clear.frame(height: 52)

                HStack(spacing: 10) {
                    BeforeAfterPanel(kind: .before, caption: "The room")
                    BeforeAfterPanel(kind: .after, caption: "One sentence later")
                }
                .frame(height: 248)
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 9) {
                    Text("Your room, with\ndifferent things in it.").question()
                    Text("Scan a room once. After that you can put anything in it and it still looks like your room — the same walls, the same window, the same light.")
                        .font(.system(size: 14))
                        .foregroundStyle(Paper.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 14) {
                    price("camera", "You walk around the room holding the phone.")
                    price("clock", "It takes about two minutes.")
                    price("house", "The phone works out the walls, the window and what's in the way.")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Paper.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer(minLength: 12)

                VStack(spacing: 11) {
                    Button(action: onScan) {
                        HStack(spacing: 9) {
                            Image(systemName: "camera").font(.system(size: 18, weight: .semibold))
                            Text("Scan a room")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Text("Pick a room you can walk all the way around.")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }

    private func price(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Paper.mutedInk)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Paper.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The before and after, drawn rather than photographed.
///
/// The design calls for two real photographs of a real room. The only rooms
/// this project has are Gal's own and they are deliberately never committed, so
/// the promise is made with a drawing that cannot be mistaken for a photo.
private struct BeforeAfterPanel: View {
    enum Kind { case before, after }

    let kind: Kind
    let caption: String

    @Environment(\.roomAccent) private var accent

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(kind == .before ? Paper.tint : Paper.deepTint)

                    // A back wall with a window in it, and a floor: the same
                    // room either way, so only the contents change.
                    Rectangle()
                        .fill(Paper.outline.opacity(kind == .before ? 0.5 : 0.35))
                        .frame(height: size.height * 0.3)
                        .offset(y: size.height * 0.7)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(kind == .before ? Paper.sheet : Color.white.opacity(0.9))
                        .frame(width: size.width * 0.3, height: size.height * 0.28)
                        .offset(x: size.width * 0.14, y: size.height * 0.2)

                    if kind == .after {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(accent.opacity(0.85))
                            .frame(width: size.width * 0.52, height: size.height * 0.17)
                            .offset(x: size.width * 0.12, y: size.height * 0.62)
                        Circle()
                            .fill(accent.opacity(0.55))
                            .frame(width: size.width * 0.16)
                            .offset(x: size.width * 0.7, y: size.height * 0.58)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Paper.mutedInk.opacity(0.5))
                            .frame(width: size.width * 0.22, height: size.height * 0.15)
                            .offset(x: size.width * 0.64, y: size.height * 0.22)
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Paper.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .frame(width: size.width * 0.5, height: size.height * 0.16)
                            .offset(x: size.width * 0.13, y: size.height * 0.63)
                    }
                }
                .frame(width: size.width, height: size.height)
            }

            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(9)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(kind == .before ? "A room before" : "The same room, redesigned")
    }
}
