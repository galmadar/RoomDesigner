import RoomPlan
import SwiftUI
import simd

/// The verdict, before any time has been spent on the room.
///
/// The one screen allowed to say the scan is not good enough yet, which is why
/// "Scan it again" sits above "Keep this room" rather than behind it. Every
/// sentence comes from ``ScanVerdict``, and so from the scan itself.
struct LearnScanDoneView: View {
    let verdict: ScanVerdict
    /// Only nil in the stand-in harness, where there is no real scan to draw.
    let room: CapturedRoom?
    let photos: [UIImage]
    let onScanAgain: () -> Void
    let onKeep: () -> Void

    @StateObject private var preview = RoomPreview()

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Scan finished")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Paper.ink)
                    .frame(height: 52)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        built
                            .padding(.horizontal, 16)
                            .padding(.top, 6)

                        summary
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                        if !photos.isEmpty {
                            photoReveal
                                .padding(.horizontal, 16)
                                .padding(.top, 22)
                        }
                    }
                    .padding(.bottom, 16)
                }

                actions
            }
        }
        .task { draw() }
    }

    // MARK: - What it built

    private var built: some View {
        ZStack(alignment: .bottomLeading) {
            FilledImage(image: preview.image, symbol: "cube.transparent")
                .frame(height: 226)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("What it built")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.black.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(10)
        }
        .accessibilityElement()
        .accessibilityLabel("The room the scan built")
    }

    /// The same opening shot "Seeing the scan" uses: from a corner, angled
    /// slightly down, which shows the floor and the far corner at once.
    private func draw() {
        guard preview.bounds == nil, let room else { return }
        let mesh = RoomGeometry.build(from: room)
        preview.load(mesh)
        let bounds = mesh.bounds
        let centre = Camera.centre(of: bounds)
        let corner = SIMD2(bounds.min.x + (bounds.max.x - bounds.min.x) * 0.18,
                           bounds.min.z + (bounds.max.z - bounds.min.z) * 0.18)
        let position = Camera.clamp(corner, in: bounds)
        let toCentre = centre - position
        preview.request(position: position, yaw: atan2(toCentre.x, -toCentre.y),
                        pitch: -8 * .pi / 180, eyeHeight: 1.5,
                        fieldOfView: 65 * .pi / 180, kind: .room, draft: false)
    }

    // MARK: - The verdict

    private var summary: some View {
        let said = verdict.concerns
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: said.isEmpty ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(said.isEmpty ? Paper.mutedInk : Paper.destructive)
                Text(verdict.headline)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.16)
                    .foregroundStyle(Paper.ink)
            }
            ForEach(said.isEmpty ? [verdict.reassurance] : said, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(Paper.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - The photos, revealed where they exist

    private var photoReveal: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 5) {
                Text("It took \(photos.count) photo\(photos.count == 1 ? "" : "s") while you walked")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.17)
                    .foregroundStyle(Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("One each time you pressed the shutter. Each remembers exactly where you were standing, so a picture can be made from that same spot later.")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 9) {
                ForEach(Array(photos.prefix(2).enumerated()), id: \.offset) { _, photo in
                    FilledImage(image: photo)
                        .frame(width: 96, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                if photos.count > 2 {
                    Text("+\(photos.count - 2) more")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.mutedInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 76)
                        .background(Paper.deepTint,
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: -

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onScanAgain) {
                Label("Scan it again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(QuietButtonStyle(height: 52))

            Button("Keep this room", action: onKeep)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 28)
    }
}
