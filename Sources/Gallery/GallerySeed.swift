import Foundation
import SwiftData
import UIKit
import simd

/// Fills the store with rooms, pictures and photographs that were never real,
/// so the gallery can be driven on a simulator.
///
/// The gallery is the one screen whose behaviour only shows up in quantity — a
/// grid of three proves nothing about a grid of ninety — and the only pictures
/// this app otherwise has are generated ones that cost money and photographs of
/// somebody's flat. So these are drawn in code: no assets, no network, nothing
/// personal. Debug-only and opt-in, exactly as `RoomSeed` is.
enum GallerySeed {

#if DEBUG
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// There is no way to tap a simulator from a script, so the screen under
    /// test is opened by name instead, the way `RoomSeed` opens the others.
    static var opensGallery: Bool { environment["GALLERY_OPEN"] == "1" }

    /// "design" or "photo": opens the newest of that kind, full screen.
    static var opensItem: String? { environment["GALLERY_OPEN_ITEM"] }

    @MainActor
    static func installIfAsked(into context: ModelContext) {
        guard environment["SEED_GALLERY"] == "1" else { return }
        let existing = try? context.fetch(FetchDescriptor<ScannedRoom>())
        guard existing?.isEmpty ?? true else { return }

        let now = Date.now
        for (index, plan) in plans.enumerated() {
            let scannedAt = now.addingTimeInterval(-plan.daysBack * 86_400)
            let room = ScannedRoom(name: plan.name, createdAt: scannedAt)
            context.insert(room)

            for shot in 0..<plan.photos {
                let (full, small) = picture(hue: plan.hue, seed: index * 100 + shot)
                let photo = ScanPhoto(takenAt: scannedAt.addingTimeInterval(Double(shot) * 90),
                                      imageData: full, thumbnailData: small,
                                      viewpoint: standInViewpoint)
                context.insert(photo)
                photo.room = room
            }

            // Spread between the scan and now, so the months actually differ.
            let span = min(plan.daysBack - 0.5, Double(plan.designs) * 3)
            for made in 0..<plan.designs {
                let offset = span * Double(made + 1) / Double(plan.designs + 1)
                let (full, small) = picture(hue: plan.hue, seed: index * 100 + 50 + made)
                let design = GeneratedPicture(
                    createdAt: scannedAt.addingTimeInterval(offset * 86_400),
                    imageData: full, thumbnailData: small,
                    prompt: prompts[(index * 7 + made) % prompts.count],
                    model: made.isMultiple(of: 3) ? .gptImage : .nanoBanana,
                    aspectRatio: "4:3",
                    angle: made.isMultiple(of: 4) ? "Free angle" : "Photo \(made % plan.photos + 1)",
                    sourcePhotoData: small,
                    scanRenderData: nil,
                    products: products(for: made))
                context.insert(design)
                design.room = room
            }

            // One room also carries a picture from the retired one-shot flow,
            // which has no date and no thumbnail of its own.
            if plan.name == "Study" {
                room.conceptImages = [picture(hue: plan.hue, seed: 999).full]
            }
        }
        try? context.save()
    }

    // MARK: - What gets made

    private struct Plan {
        let name: String
        let hue: Double
        let designs: Int
        let photos: Int
        /// Days before now that the room was scanned.
        let daysBack: Double
    }

    /// Eight rooms over five months. One was photographed and never designed,
    /// so the grid has to cope with a room that contributes nothing but
    /// photographs; one was scanned yesterday and barely designed, so the top
    /// of the grid is the mixture the screen actually has to be read through.
    private static let plans: [Plan] = [
        Plan(name: "Dining room", hue: 0.95, designs: 2,  photos: 4, daysBack: 1),
        Plan(name: "Living room", hue: 0.07, designs: 14, photos: 6, daysBack: 6),
        Plan(name: "Bedroom",     hue: 0.60, designs: 11, photos: 5, daysBack: 22),
        Plan(name: "Kitchen",     hue: 0.33, designs: 9,  photos: 4, daysBack: 49),
        Plan(name: "Study",       hue: 0.09, designs: 12, photos: 5, daysBack: 75),
        Plan(name: "Guest room",  hue: 0.78, designs: 7,  photos: 4, daysBack: 97),
        Plan(name: "Hallway",     hue: 0.53, designs: 0,  photos: 3, daysBack: 119),
        Plan(name: "Balcony",     hue: 0.16, designs: 5,  photos: 3, daysBack: 141),
    ]

    private static let prompts = [
        "Warmer, with a big rug and somewhere to read",
        "Less furniture, more light",
        "Darker walls and a low shelf along the window",
        "Something calmer, mostly wood and linen",
        "A green wall and one large plant",
        "Move the sofa to face the window",
        "Plainer, with nothing on the floor",
    ]

    private static func products(for index: Int) -> [UsedProduct] {
        switch index % 3 {
        case 0: return []
        case 1: return [UsedProduct(name: "Low oak shelf", libraryObjectID: nil, marker: .blue)]
        default: return [UsedProduct(name: "Linen sofa", libraryObjectID: nil, marker: .green),
                         UsedProduct(name: "Paper lamp", libraryObjectID: nil, marker: .yellow)]
        }
    }

    /// A pose that is nowhere in particular. Enough for `ScanPhoto` to store;
    /// it lines up with no scan, and the photo screens say so rather than lie.
    private static var standInViewpoint: PhotoViewpoint {
        PhotoViewpoint(transform: matrix_identity_float4x4,
                       intrinsics: simd_float3x3(SIMD3(1400, 0, 0),
                                                 SIMD3(0, 1400, 0),
                                                 SIMD3(960, 720, 1)),
                       imageResolution: SIMD2(1920, 1440),
                       orientation: .landscapeRight)
    }

    // MARK: - Drawing a room that does not exist

    /// A full-size JPEG and its thumbnail, at the sizes the real ones come in,
    /// so the grid is exercised against the same weight of data it will meet.
    ///
    /// Designs and photographs are drawn by the same code on purpose. They look
    /// alike in real life, which is the whole reason the gallery has to say
    /// which is which; seeding two obviously different kinds of picture would
    /// test the label against a problem it does not have.
    private static func picture(hue: Double, seed: Int) -> (full: Data, thumbnail: Data) {
        let size = CGSize(width: 1440, height: 1080)
        let image = draw(hue: hue, seed: seed, size: size)
        let small = draw(hue: hue, seed: seed, size: CGSize(width: 400, height: 300))
        return (image.jpegData(compressionQuality: 0.8) ?? Data(),
                small.jpegData(compressionQuality: 0.7) ?? Data())
    }

    private static func draw(hue: Double, seed: Int, size: CGSize) -> UIImage {
        var rng = Roll(seed: UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let canvas = context.cgContext
            let width = size.width, height = size.height

            // Everything is drawn around the room's own hue, because the app
            // takes a room's colour from the pixels of its first photograph —
            // seeding pictures that all share one brown floor would give eight
            // rooms the same accent and prove nothing about telling them apart.
            let roomHue = CGFloat(hue.truncatingRemainder(dividingBy: 1))

            UIColor(hue: roomHue, saturation: 0.10 + 0.08 * rng.next(),
                    brightness: 0.76 + 0.18 * rng.next(), alpha: 1).setFill()
            canvas.fill(CGRect(origin: .zero, size: size))

            // A window, which is what makes a flat rectangle read as a room.
            let windowWidth = width * (0.18 + 0.16 * rng.next())
            let windowX = width * (0.08 + 0.55 * rng.next())
            UIColor(white: 0.96, alpha: 1).setFill()
            canvas.fill(CGRect(x: windowX, y: height * 0.12,
                               width: windowWidth, height: height * 0.36))

            // The floor is most of the frame, so it is mostly what the room's
            // colour gets taken from.
            let floorTop = height * (0.58 + 0.08 * rng.next())
            UIColor(hue: roomHue, saturation: 0.34 + 0.18 * rng.next(),
                    brightness: 0.34 + 0.18 * rng.next(), alpha: 1).setFill()
            canvas.fill(CGRect(x: 0, y: floorTop, width: width, height: height - floorTop))

            // A rug, laid on the floor rather than floating on the wall.
            UIColor(hue: (roomHue + 0.06).truncatingRemainder(dividingBy: 1),
                    saturation: 0.30 + 0.18 * rng.next(),
                    brightness: 0.48 + 0.18 * rng.next(), alpha: 1).setFill()
            canvas.fillEllipse(in: CGRect(x: width * 0.12, y: floorTop + (height - floorTop) * 0.28,
                                          width: width * 0.66, height: (height - floorTop) * 0.6))

            for _ in 0..<(3 + Int(rng.next() * 3)) {
                let blockWidth = width * (0.12 + 0.24 * rng.next())
                let blockHeight = height * (0.10 + 0.26 * rng.next())
                let x = width * rng.next() * 0.82
                let y = floorTop - blockHeight * (0.5 + 0.5 * rng.next())
                UIColor(hue: (roomHue + 1 + 0.10 * rng.signed()).truncatingRemainder(dividingBy: 1),
                        saturation: 0.14 + 0.30 * rng.next(),
                        brightness: 0.30 + 0.46 * rng.next(), alpha: 1).setFill()
                let block = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: blockWidth,
                                                             height: blockHeight),
                                         cornerRadius: min(blockWidth, blockHeight) * 0.12)
                block.fill()
            }

            // Light falling off towards the floor, so it is not a flat collage.
            let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [UIColor.black.withAlphaComponent(0).cgColor,
                                            UIColor.black.withAlphaComponent(0.30).cgColor] as CFArray,
                                   locations: [0, 1])
            if let shade {
                canvas.drawLinearGradient(shade, start: CGPoint(x: 0, y: 0),
                                          end: CGPoint(x: 0, y: height), options: [])
            }
        }
    }

    /// SplitMix64, so a room looks the same every time it is seeded.
    private struct Roll {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> Double {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(1 << 53)
        }

        mutating func signed() -> Double { next() * 2 - 1 }
    }
#else
    static var opensGallery: Bool { false }
    static var opensItem: String? { nil }

    @MainActor
    static func installIfAsked(into context: ModelContext) {}
#endif
}
