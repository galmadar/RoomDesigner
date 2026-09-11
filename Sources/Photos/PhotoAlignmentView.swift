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
                Text("This photo couldn't be opened.").foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
        .overlay(alignment: .bottom) { notes }
        .task { await load() }
    }

    private var viewpoint: PhotoViewpoint? {
        guard let taken = photo.viewpoint else { return nil }
        if corrects, let alignment { return taken.transformed(by: alignment.correction) }
        return taken
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(showsLines
                 ? "If the lines sit on the real walls and floor, the photo lines up with the scan. Tap the photo to hide them."
                 : "Tap the photo to show the lines again.")
            if let check = photo.viewpoint?.arkitCheckPixels {
                Text("Camera maths vs ARKit: \(check, format: .number.precision(.fractionLength(1))) px")
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let alignment {
                Text(alignment.summary).foregroundStyle(.white.opacity(0.7))
                if !alignment.isNegligible {
                    Toggle("Correct for the difference", isOn: $corrects)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .padding()
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
