import RoomPlan
import SwiftUI

/// A scan photo with the scan's outlines drawn over it through the photo's own
/// renderer camera. Lines on the real walls mean pose, lens and frame agree.
struct PhotoAlignmentView: View {
    let photo: ScanPhoto
    let room: ScannedRoom

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false
    @State private var edges: [ScanOutlines.Edge] = []
    @State private var alignment: ScanAlignment?
    @State private var showsLines = true
    @State private var corrects = false
    @State private var isPlacing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay { if showsLines, let viewpoint { outlines(viewpoint) } }
                    .onTapGesture { showsLines.toggle() }
            } else if failed {
                Text("This photo couldn't be opened.")
                    .font(.system(size: 15))
                    .foregroundStyle(Paper.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 56)
                    .paperCard()
            } else {
                ProgressView().tint(Paper.fallbackAccent)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Paper.ink)
                    .frame(width: 44, height: 44)
                    .background(Paper.card, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
            }
            .padding(16)
            .accessibilityLabel("Done")
        }
        .overlay(alignment: .bottom) { notes }
        .task { await load() }
        .fullScreenCover(isPresented: $isPlacing) { PhotoPlaceFlow(room: room, photo: photo) }
    }

    private var viewpoint: PhotoViewpoint? {
        guard let taken = photo.viewpoint else { return nil }
        if corrects, let alignment { return taken.transformed(by: alignment.correction) }
        return taken
    }

    @ViewBuilder private var notes: some View {
        if photo.isPlaced { placedNotes } else { unplacedNotes }
    }

    /// Nothing can be drawn over a photo that has no pose — there is no camera
    /// to project through — so this says so plainly and offers the way out
    /// rather than showing an empty overlay and leaving it a mystery.
    private var unplacedNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This photo has no place in the room yet, so there is nothing to draw over it and no spot to stand you in.")
                .foregroundStyle(Paper.ink)
            Button("Place it") { isPlacing = true }
                .buttonStyle(QuietButtonStyle(height: 44))
        }
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .paperCard(radius: 16)
        .padding(16)
    }

    private var placedNotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(showsLines
                 ? "If the lines sit on the real walls and floor, the photo lines up with the scan. Tap the photo to hide them."
                 : "Tap the photo to show the lines again.")
                .foregroundStyle(Paper.ink)
            if photo.isUploaded {
                Text(photo.caption).foregroundStyle(Paper.secondaryInk)
                Button("Move it") { isPlacing = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Paper.fallbackAccent)
                    .frame(minHeight: 30)
            }
            if let check = photo.viewpoint?.arkitCheckPixels {
                Text("Camera maths vs ARKit: \(check, format: .number.precision(.fractionLength(1))) px")
                    .foregroundStyle(Paper.secondaryInk)
            }
            if let alignment {
                Text(alignment.summary).foregroundStyle(Paper.secondaryInk)
                if !alignment.isNegligible {
                    Toggle("Correct for the difference", isOn: $corrects)
                        .foregroundStyle(Paper.ink)
                        .tint(Paper.fallbackAccent)
                }
            }
        }
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .paperCard(radius: 16)
        .padding(16)
    }

    private func outlines(_ viewpoint: PhotoViewpoint) -> some View {
        let projector = PhotoProjector(viewpoint)
        return Canvas { context, size in
            for edge in edges {
                guard let segment = projector.segment(edge.start, edge.end) else { continue }
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(segment.0.x) * size.width,
                                      y: CGFloat(segment.0.y) * size.height))
                path.addLine(to: CGPoint(x: CGFloat(segment.1.x) * size.width,
                                         y: CGFloat(segment.1.y) * size.height))
                let width: CGFloat = edge.kind == .object ? 1.5 : 2.5
                // A dark halo keeps the line readable over a white wall.
                context.stroke(path, with: .color(.black.opacity(0.45)), lineWidth: width + 2)
                context.stroke(path, with: .color(colour(edge.kind)), lineWidth: width)
            }
        }
        .allowsHitTesting(false)
    }

    private func colour(_ kind: ScanOutlines.Kind) -> Color {
        switch kind {
        case .wall: return .yellow
        case .floor: return .cyan
        case .door: return .orange
        case .window: return .blue
        case .object: return .green
        }
    }

    private func load() async {
        let data = photo.imageData
        let decoded = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
        image = decoded
        failed = decoded == nil

        guard let captured = room.capturedRoom else { return }
        edges = ScanOutlines.edges(of: captured)
        alignment = room.liveRoom.flatMap { ScanAlignment(live: $0, processed: captured) }
    }
}
