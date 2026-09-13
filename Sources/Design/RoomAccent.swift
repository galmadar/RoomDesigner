import ImageIO
import SwiftData
import SwiftUI

/// Each room opens in its own colour, taken from its own first scan photo.
///
/// The hue is the saturation-weighted circular mean of the photo's pixels, which
/// finds the floor and the walls rather than the one bright cushion an average
/// would smear away. Only the hue is kept: saturation and brightness are pinned
/// to a band that stays legible as a button behind white text, so a grey-blue
/// bedroom and an oak living room differ in colour without differing in weight.
@MainActor
final class RoomAccents: ObservableObject {
    static let shared = RoomAccents()

    /// Derived once per room and kept for the session; deriving it is a decode.
    @Published private(set) var hues: [PersistentIdentifier: Double] = [:]
    private var asked: Set<PersistentIdentifier> = []

    private init() {}

    func accent(for room: ScannedRoom) -> Color {
        hues[room.persistentModelID].map(Self.colour(hue:)) ?? Paper.fallbackAccent
    }

    func load(_ room: ScannedRoom) async {
        let id = room.persistentModelID
        guard !asked.contains(id) else { return }
        asked.insert(id)
        // The thumbnail is enough: the hue of a room does not live in its detail.
        guard let data = room.sortedPhotos.first.flatMap({ $0.thumbnailData ?? $0.imageData })
        else { return }
        guard let hue = await Task.detached(priority: .utility, operation: {
            Self.hue(from: data)
        }).value else { return }
        hues[id] = hue
    }

    static func colour(hue: Double) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hue: hue, saturation: 0.52, brightness: 0.84, alpha: 1)
                : UIColor(hue: hue, saturation: 0.62, brightness: 0.70, alpha: 1)
        })
    }

    /// 0...1. Nil for a photo with no colour in it at all, which falls back.
    nonisolated static func hue(from image: Data) -> Double? {
        let side = 24
        guard let source = CGImageSourceCreateWithData(image as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: side,
              ] as CFDictionary)
        else { return nil }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = pixels.withUnsafeMutableBytes({ bytes in
            CGContext(data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8,
                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return nil }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: side, height: side))

        var x = 0.0, y = 0.0, weight = 0.0
        for start in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[start]) / 255
            let g = Double(pixels[start + 1]) / 255
            let b = Double(pixels[start + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            let delta = high - low
            // Near-grey, near-black and blown-out pixels have no hue worth trusting.
            guard delta > 0.04, high > 0.12, high < 0.98 else { continue }

            var degrees: Double
            if high == r { degrees = (g - b) / delta }
            else if high == g { degrees = 2 + (b - r) / delta }
            else { degrees = 4 + (r - g) / delta }
            degrees *= 60
            if degrees < 0 { degrees += 360 }

            let radians = degrees * .pi / 180
            let strength = (delta / high) * delta
            x += cos(radians) * strength
            y += sin(radians) * strength
            weight += strength
        }
        guard weight > 0 else { return nil }
        var mean = atan2(y, x) * 180 / .pi
        if mean < 0 { mean += 360 }
        return mean / 360
    }
}

private struct RoomAccentKey: EnvironmentKey {
    static let defaultValue = Paper.fallbackAccent
}

extension EnvironmentValues {
    /// The colour of the room being looked at, for anything drawn inside it.
    var roomAccent: Color {
        get { self[RoomAccentKey.self] }
        set { self[RoomAccentKey.self] = newValue }
    }
}
