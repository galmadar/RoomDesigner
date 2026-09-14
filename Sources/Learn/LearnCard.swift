import SwiftUI

/// A lesson attached to the screen it is about.
///
/// It never gets a screen of its own, it goes away with one tap, and it is laid
/// out so that the thing it describes stays visible above it.
struct LearnCard: View {
    let title: String
    let lines: [String]
    let onDismiss: () -> Void

    @Environment(\.roomAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.38)
                .foregroundStyle(Paper.ink)

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer(minLength: 0)
                Button("Got it", action: onDismiss)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .padding(.top, 7)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Paper.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 17, y: 10)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}
