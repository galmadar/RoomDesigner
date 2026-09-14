import SwiftData
import SwiftUI

/// One page of a room's carousel.
///
/// The order is newest-first and never changes: what is being made, then the
/// pictures, then the photos of the room as it really is. A picture being made
/// sits first so that when it lands it takes the same page it was waiting on,
/// and the page you are reading does not move under you.
enum RoomPage: Identifiable {
    case making(PhotoDesignRun)
    case picture(RoomPicture)
    case photo(ScanPhoto)

    var id: String {
        switch self {
        case .making(let job): return "making-\(job.id.uuidString)"
        case .picture(let picture): return "picture-\(picture.id)"
        case .photo(let photo): return "photo-\(photo.persistentModelID.hashValue)"
        }
    }
}

/// Everything there is to look at in one room, a swipe apart.
struct PictureCarousel: View {
    let cards: [RoomPage]
    @Binding var selection: String
    let onOpen: (RoomPage) -> Void

    @Environment(\.roomAccent) private var accent

    static let height: CGFloat = 430

    /// Past this many, dots are no longer something you can count at a glance.
    private static let dotLimit = 8

    private var index: Int { cards.firstIndex { $0.id == selection } ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(cards) { card in
                    page(card).tag(card.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Self.height)
            indicator
        }
        // A finished picture takes the vanished job's page; a deleted one leaves
        // a selection pointing at nothing, which shows a blank carousel.
        .task(id: cards.map(\.id)) {
            if !cards.contains(where: { $0.id == selection }) {
                selection = cards.first?.id ?? ""
            }
        }
    }

    @ViewBuilder private func page(_ card: RoomPage) -> some View {
        switch card {
        case .making(let job):
            MakingPictureHero(job: job)
        case .picture(let picture):
            Button { onOpen(card) } label: {
                CarouselPage(data: picture.fullData, title: picture.prompt,
                             caption: picture.caption, markers: picture.markers, glyph: nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Picture. \(picture.prompt)")
        case .photo(let photo):
            // A photo with no spot says so on its face and offers the way out.
            // It is not a dead end and it is not a nag: the page reads the same
            // as any other and the offer only costs a tap if it is wanted.
            Button { onOpen(card) } label: {
                CarouselPage(data: photo.imageData,
                             title: photo.isPlaced ? "Photo of the real room"
                                                   : "Photo with no place yet",
                             caption: photo.caption, markers: [],
                             glyph: photo.isPlaced ? "camera" : "mappin.slash",
                             action: photo.isPlaced ? nil : "Place it")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo.isPlaced
                                ? "Photo of the real room"
                                : "Photo with no place in the room yet. Place it.")
        }
    }

    @ViewBuilder private var indicator: some View {
        if cards.count > 1 {
            Group {
                if cards.count <= Self.dotLimit {
                    HStack(spacing: 6) {
                        ForEach(cards) { card in
                            Capsule()
                                .fill(card.id == selection ? accent : Paper.outline)
                                .frame(width: card.id == selection ? 18 : 6, height: 6)
                        }
                    }
                } else {
                    Text("\(index + 1) of \(cards.count)")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .accessibilityElement()
            .accessibilityLabel("\(index + 1) of \(cards.count)")
        }
    }
}

/// A picture filling the top of the room, with what it is written across it.
private struct CarouselPage: View {
    let data: Data?
    let title: String
    let caption: String
    let markers: [Marker]
    /// Set for a photo of the real room, so it is not read as a design.
    let glyph: String?
    /// The one thing this page is still waiting to be told, if anything.
    var action: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PictureThumbnail(data: data, maxPixelSize: 1400)
                .frame(height: PictureCarousel.height)
                .frame(maxWidth: .infinity)

            LinearGradient(colors: [Color(red: 0.11, green: 0.098, blue: 0.09).opacity(0.72),
                                    .clear],
                           startPoint: .bottom, endPoint: .top)
                .frame(height: 130)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    if let glyph {
                        Image(systemName: glyph)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                        MarkerDot(marker: marker, size: 9)
                    }
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                    if let action {
                        Text(action)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.11, green: 0.098, blue: 0.09))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(.white.opacity(0.9), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(height: PictureCarousel.height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
