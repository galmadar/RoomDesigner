#if DEBUG
import Foundation
import RoomPlan
import SwiftData
import SwiftUI
import UIKit
import simd

/// Fills a room with pictures and photos that were never made, so the carousel
/// at the top of a room can be driven on a simulator.
///
/// Debug only and opt-in, like ``RoomSeed`` beside it. Nothing here is a scan
/// and nothing here was generated: real pictures and real scans are somebody's
/// home and stay on their phone.
@MainActor
enum DemoContents {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// "3x2" — three pictures and two photos of the real room.
    static var wanted: (pictures: Int, photos: Int)? {
        guard let value = env["DEMO_ROOM"] else { return nil }
        let parts = value.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    /// Adds a picture being made, frozen, as the carousel's first page.
    static var wantsMaking: Bool { env["DEMO_MAKING"] == "1" }

    /// The page the carousel opens on, counting from zero.
    static var page: Int? { env["DEMO_PAGE"].flatMap { Int($0) } }

    private static var roomName: String { env["DEMO_ROOM_NAME"] ?? "Room 2" }

    private static let briefs = [
        "Calm minimalist living space, concrete floor, natural linen sofa, diffused window light",
        "Warm oak and cream, low shelving, one big plant in the corner",
        "Dark green walls, a brass lamp, a deep armchair by the window",
        "Pale wood and white cotton, nothing on the floor that does not need to be",
        "Terracotta and clay, a long low bench, late afternoon light",
        "Charcoal and bone, one framed print, a rug over most of the floor",
    ]

    static func install(into context: ModelContext) {
        // Said out loud on every demo launch: a run driven from a script must be
        // provably not pointed at the paid service, and an empty override falls
        // back to it rather than to nothing.
        NSLog("DemoContents: requests would go to %@", "\(PlanService.baseURL)")
        guard let wanted else { return }
        let name = roomName
        let found = try? context.fetch(
            FetchDescriptor<ScannedRoom>(predicate: #Predicate { $0.name == name }))
        if let room = found?.first { return showMaking(in: room) }

        let room = ScannedRoom(name: name)
        room.capturedRoomData = scanData()
        context.insert(room)

        for index in 0..<wanted.pictures {
            let image = design(index)
            let picture = GeneratedPicture(
                createdAt: .now.addingTimeInterval(TimeInterval(index) * -3600),
                imageData: image.jpegData(compressionQuality: 0.9) ?? Data(),
                thumbnailData: small(image).jpegData(compressionQuality: 0.8),
                prompt: briefs[index % briefs.count],
                model: .nanoBanana,
                aspectRatio: "3:4",
                angle: index == 0 ? "Free angle" : "Photo \(index)",
                sourcePhotoData: nil,
                scanRenderData: nil,
                products: [])
            context.insert(picture)
            // A fresh array, never an append in place: SwiftData may not see one.
            room.pictures = (room.pictures ?? []) + [picture]
        }

        for index in 0..<wanted.photos {
            let image = photo(index)
            let shot = ScanPhoto(takenAt: .now.addingTimeInterval(TimeInterval(index) * 30 - 86400),
                                 imageData: image.jpegData(compressionQuality: 0.9) ?? Data(),
                                 thumbnailData: small(image).jpegData(compressionQuality: 0.8),
                                 viewpoint: viewpoint())
            context.insert(shot)
            room.photos = (room.photos ?? []) + [shot]
        }

        try? context.save()
        showMaking(in: room)
    }

    private static func showMaking(in room: ScannedRoom) {
        guard wantsMaking else { return }
        PictureJobs.shared.showStandIn(for: room, prompt: briefs[0])
    }

    // MARK: - A room without a scan

    /// RoomPlan will not make a `CapturedRoom` on a simulator and a real one is
    /// somebody's flat, so the demo room decodes an empty scan. The shape is the
    /// framework's rather than ours, so a failure is logged, not swallowed.
    private static func scanData() -> Data? {
        let empty = """
        {"identifier":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","version":3,"story":0,\
        "walls":[],"doors":[],"windows":[],"openings":[],"objects":[],"floors":[],"sections":[]}
        """
        let data = env["DEMO_SCAN"].flatMap { Data(base64Encoded: $0) } ?? Data(empty.utf8)
        do {
            _ = try JSONDecoder().decode(CapturedRoom.self, from: data)
            return data
        } catch {
            NSLog("DemoContents: the demo scan did not decode — %@", "\(error)")
            return nil
        }
    }

    private static func viewpoint() -> PhotoViewpoint {
        PhotoViewpoint(transform: matrix_identity_float4x4,
                       intrinsics: simd_float3x3(SIMD3(1500, 0, 0),
                                                 SIMD3(0, 1500, 0),
                                                 SIMD3(960, 720, 1)),
                       imageResolution: SIMD2(1920, 1440),
                       orientation: .portrait,
                       timestamp: 0,
                       arkitCheckPixels: nil)
    }

    // MARK: - Pictures that are plainly not photographs

    private static let size = CGSize(width: 1024, height: 1365)

    private static func small(_ image: UIImage) -> UIImage {
        let side = CGSize(width: 320, height: 427)
        return UIGraphicsImageRenderer(size: side).image { _ in
            image.draw(in: CGRect(origin: .zero, size: side))
        }
    }

    private static func design(_ index: Int) -> UIImage {
        let hues: [CGFloat] = [0.09, 0.12, 0.05, 0.14, 0.03, 0.07]
        let hue = hues[index % hues.count]
        return UIGraphicsImageRenderer(size: size).image { ctx in
            gradient(ctx.cgContext,
                     from: UIColor(hue: hue, saturation: 0.16, brightness: 0.96, alpha: 1),
                     to: UIColor(hue: hue, saturation: 0.28, brightness: 0.76, alpha: 1))
            UIColor(white: 1, alpha: 0.5).setFill()
            UIBezierPath(rect: CGRect(x: size.width * 0.56, y: size.height * 0.14,
                                      width: size.width * 0.32, height: size.height * 0.34)).fill()
            UIColor(hue: hue, saturation: 0.34, brightness: 0.58, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: size.height * 0.7,
                                      width: size.width, height: size.height * 0.3)).fill()
            UIColor(hue: hue, saturation: 0.2, brightness: 0.9, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: size.width * 0.08, y: size.height * 0.56,
                                             width: size.width * 0.56, height: size.height * 0.2),
                         cornerRadius: 34).fill()
            number(index + 1, colour: UIColor(white: 1, alpha: 0.55))
        }
    }

    /// Duller and flatter than a design, and warm: the room's colour is taken
    /// from its photos, so a grey stand-in would tint the whole screen grey.
    private static func photo(_ index: Int) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            gradient(ctx.cgContext,
                     from: UIColor(hue: 0.08, saturation: 0.07, brightness: 0.87, alpha: 1),
                     to: UIColor(hue: 0.08, saturation: 0.13, brightness: 0.66, alpha: 1))
            UIColor(hue: 0.1, saturation: 0.04, brightness: 0.97, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: size.width * (0.12 + 0.13 * CGFloat(index % 3)),
                                      y: size.height * 0.2,
                                      width: size.width * 0.33, height: size.height * 0.36)).fill()
            UIColor(hue: 0.08, saturation: 0.32, brightness: 0.47, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: size.height * 0.72,
                                      width: size.width, height: size.height * 0.28)).fill()
            number(index + 1, colour: UIColor(white: 1, alpha: 0.45))
        }
    }

    private static func gradient(_ context: CGContext, from: UIColor, to: UIColor) {
        guard let ramp = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [from.cgColor, to.cgColor] as CFArray,
                                    locations: [0, 1]) else { return }
        context.drawLinearGradient(ramp, start: .zero,
                                   end: CGPoint(x: 0, y: size.height), options: [])
    }

    private static func number(_ value: Int, colour: UIColor) {
        let text = "\(value)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 240, weight: .ultraLight),
            .foregroundColor: colour,
        ]
        let box = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (size.width - box.width) / 2, y: size.height * 0.03),
                  withAttributes: attributes)
    }
}

/// Hangs the demo contents off the app's one window, beside `RoomSeeding`.
struct DemoSeeding: ViewModifier {
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.task { DemoContents.install(into: context) }
    }
}
#endif
