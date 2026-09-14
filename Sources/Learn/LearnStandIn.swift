#if DEBUG
import SwiftUI

/// A way to put the scan's three screens on a simulator.
///
/// RoomPlan needs a LiDAR device, so none of the scanning screens can be
/// reached without one. This renders them from fabricated state instead, marked
/// on screen so that a screenshot of one can never be mistaken for a real scan.
/// Debug only, and driven the way `OPEN_ROOM` already is:
///
///     xcrun simctl launch <sim> <bundle> with SIMCTL_CHILD_LEARN_STANDIN set.
enum LearnStandIn: String, Identifiable {
    case scanReady
    case scanCoach
    case scanCoachClean
    case scanDone
    case scanDoneThin
    case whereCard
    case firstPicture
    /// Reachable for real under the gear, but not on a fresh install, where the
    /// first-launch screen is in front of it.
    case help

    var id: String { rawValue }

    static var requested: LearnStandIn? {
        ProcessInfo.processInfo.environment["LEARN_STANDIN"].flatMap(LearnStandIn.init(rawValue:))
    }
}

struct LearnStandInView: View {
    let screen: LearnStandIn

    @StateObject private var coach = ScanCoach()

    var body: some View {
        ZStack(alignment: .top) {
            content
            Text("STAND-IN — fabricated state, not a real scan")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Paper.destructive, in: Capsule())
                .padding(.top, 2)
        }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .scanReady:
            LearnScanReadyView(onStart: {}, onCancel: {})

        case .scanCoach, .scanCoachClean:
            ZStack {
                cameraStandIn
                ScanCoachOverlay(coach: coach, photoCount: 6, isFinishing: false,
                                 onCancel: {}, onShutter: {}, onFinish: {})
            }
            .task {
                if screen == .scanCoach {
                    coach.standIn(found: 4, joined: 3,
                                  correction: .init(title: "Slow down",
                                                    detail: "Sweep along the wall — don't swing past it."),
                                  aim: CGPoint(x: 0.36, y: 0.34))
                } else {
                    coach.standIn(found: 4, joined: 4, correction: nil, aim: nil)
                }
            }

        case .scanDone:
            LearnScanDoneView(
                verdict: ScanVerdict(standInWalls: 4, windows: 1, doors: 1, objects: 3, unjoined: 0),
                room: nil, photos: swatches(6), onScanAgain: {}, onKeep: {})

        case .scanDoneThin:
            LearnScanDoneView(
                verdict: ScanVerdict(standInWalls: 4, windows: 1, doors: 1, objects: 3, unjoined: 1),
                room: nil, photos: swatches(6), onScanAgain: {}, onKeep: {})

        case .whereCard:
            ZStack(alignment: .bottom) {
                photoGridStandIn
                Color.black.opacity(0.46).ignoresSafeArea()
                LearnCard(
                    title: "Stand where you stood",
                    lines: ["While you were scanning, the app kept a photo at each of these spots and remembered exactly where you were standing. Choose one and the picture is made from there, so it lines up with the room you already know.",
                            "Any angle works too. It just has no photograph to match."],
                    onDismiss: {})
                    .padding(.bottom, 26)
            }

        case .firstPicture:
            LearnFirstPictureView(picture: Self.standInPicture())

        case .help:
            LearnHelpView()
        }
    }

    // MARK: - Fabricated backdrops

    private var cameraStandIn: some View {
        LinearGradient(colors: [Color(white: 0.30), Color(white: 0.12)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Text("camera feed")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .ignoresSafeArea()
    }

    private var photoGridStandIn: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("Where are you\nstanding?").question()
                HStack(spacing: 12) {
                    ForEach(0..<2, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(index == 0 ? Paper.deepTint : Paper.tint)
                            .frame(height: 186)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
        }
    }

    /// Flat colour tiles: a photo of a room is exactly what a stand-in must not
    /// pretend to have.
    private func swatches(_ count: Int) -> [UIImage] {
        (0..<count).map { index in
            Self.swatch(hue: Double(index) / Double(max(count, 1)))
        }
    }

    private static func swatch(hue: Double) -> UIImage {
        let size = CGSize(width: 240, height: 180)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: hue, saturation: 0.22, brightness: 0.78, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func standInPicture() -> GeneratedPicture {
        let made = swatch(hue: 0.08).jpegData(compressionQuality: 0.8) ?? Data()
        let photo = swatch(hue: 0.55).jpegData(compressionQuality: 0.8)
        let scan = swatch(hue: 0.0).jpegData(compressionQuality: 0.8)
        return GeneratedPicture(
            imageData: made, thumbnailData: made,
            prompt: "Warm and cosy for winter evenings",
            model: .nanoBanana, aspectRatio: "4:3", angle: "Photo 1",
            sourcePhotoData: photo, scanRenderData: scan, products: [])
    }
}
#endif
