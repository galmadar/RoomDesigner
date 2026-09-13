import SwiftUI
import simd

/// The eight box colours, and the one place they are defined.
///
/// Two values per colour because they do two different jobs. `rgb` is painted
/// into the scan render the model is shown, so it has to stay saturated and far
/// from the scan's off-white walls, oak floor and grey furniture. `color` is the
/// same colour on screen — the plan box, the product row, the dot under a saved
/// picture — where saturated reads as garish, so it is the softer drawn value.
/// The name is what the server matches on, so the case order is the server's.
enum Marker: String, CaseIterable, Codable {
    case red, blue, yellow, green, purple, orange, cyan, magenta

    /// What the renderer paints the box, for the image model to find.
    var rgb: SIMD3<Float> {
        switch self {
        case .red:     return SIMD3(0.92, 0.10, 0.10)
        case .blue:    return SIMD3(0.10, 0.30, 0.95)
        case .yellow:  return SIMD3(1.00, 0.88, 0.05)
        case .green:   return SIMD3(0.10, 0.78, 0.20)
        case .purple:  return SIMD3(0.55, 0.15, 0.80)
        case .orange:  return SIMD3(1.00, 0.50, 0.00)
        case .cyan:    return SIMD3(0.00, 0.85, 0.90)
        case .magenta: return SIMD3(0.95, 0.10, 0.80)
        }
    }

    /// The same product's colour wherever it appears on screen.
    var color: Color {
        switch self {
        case .red:     return Color(uiColor: UIColor(rgb: 0xD93B3B))
        case .blue:    return Color(uiColor: UIColor(rgb: 0x2F6FEB))
        case .yellow:  return Color(uiColor: UIColor(rgb: 0xD9A520))
        case .green:   return Color(uiColor: UIColor(rgb: 0x2E9E6B))
        case .purple:  return Color(uiColor: UIColor(rgb: 0x8B4FC4))
        case .orange:  return Color(uiColor: UIColor(rgb: 0xE0701F))
        case .cyan:    return Color(uiColor: UIColor(rgb: 0x1897B0))
        case .magenta: return Color(uiColor: UIColor(rgb: 0xC93E96))
        }
    }

    var label: String { rawValue.capitalized }
}

/// A product's colour as a dot, the size the design draws it.
struct MarkerDot: View {
    let marker: Marker?
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(marker?.color ?? .clear)
            .overlay {
                if marker == nil {
                    Circle().strokeBorder(Paper.outline, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
