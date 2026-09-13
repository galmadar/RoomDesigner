import SwiftUI

/// The palette the redesign is drawn in.
///
/// Light is the mockup's values exactly. Dark is the same roles in warm dark —
/// paper darkens, ink lightens, the card stays the one surface that lifts —
/// so no screen has to be pinned to one appearance.
enum Paper {

    /// Warm paper behind everything.
    static let sheet = dynamic(light: 0xFAF8F5, dark: 0x16130F)

    /// Soft tint for quiet controls.
    static let tint = dynamic(light: 0xF2EDE6, dark: 0x262019)

    /// White only for a card that holds something.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1F1A15)

    static let ink = dynamic(light: 0x1C1917, dark: 0xF5F1EA)

    static let secondaryInk = dynamic(light: 0x79706A, dark: 0xA79D92)

    /// The label on a quiet button — darker than secondary text, lighter than ink.
    static let quietInk = dynamic(light: 0x6D6157, dark: 0xC4B8AB)

    /// Icons and placeholder text inside tinted tiles.
    static let mutedInk = dynamic(light: 0x96806A, dark: 0x8C7B68)

    /// The dashed outline of an empty slot.
    static let outline = dynamic(light: 0xDDD4C8, dark: 0x40342A)

    /// A filled tile one step warmer than `tint`, for "+2 more".
    static let deepTint = dynamic(light: 0xEFE7DC, dark: 0x2E261E)

    /// Where a room has no photo to take its colour from.
    static let fallbackAccent = dynamic(light: 0xB8763C, dark: 0xD9924F)

    static let cardShadow = Color(
        uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.5)
            : UIColor(red: 28 / 255, green: 25 / 255, blue: 23 / 255, alpha: 0.07) })

    // MARK: -

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Shapes and type

extension View {
    /// A white card with the one shadow the design uses.
    func paperCard(radius: CGFloat = 18) -> some View {
        background(Paper.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Paper.cardShadow, radius: 1.5, x: 0, y: 1)
    }

    /// The big question at the top of a step.
    func question() -> some View {
        font(.system(size: 28, weight: .semibold))
            .tracking(-0.84)                    // -0.03em at 28 pt
            .foregroundStyle(Paper.ink)
            .lineSpacing(0)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A picture that fills the box it is given without the box growing to fit it.
///
/// `scaledToFill` on its own offers the picture's real width to the layout, so a
/// landscape photo in a grid cell pushes the whole screen sideways. As an
/// overlay it cannot: the box is sized first and the picture is clipped to it.
struct FilledImage: View {
    let image: UIImage?
    var symbol: String?

    var body: some View {
        Paper.tint
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let symbol {
                    Image(systemName: symbol).foregroundStyle(Paper.mutedInk)
                }
            }
            .clipped()
    }
}

// MARK: - Buttons

/// The one filled action a screen is allowed.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.roomAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .tracking(-0.18)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.38)
    }
}

/// Never two filled buttons on one screen: everything else is tinted.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16))
            .foregroundStyle(Paper.quietInk)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

// MARK: - Step dots

/// Where you are in the three questions, shown in the navigation bar.
struct StepDots: View {
    let step: Int
    var count = 3

    @Environment(\.roomAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == step ? accent : Paper.outline)
                    .frame(width: index == step ? 20 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(count)")
    }
}
