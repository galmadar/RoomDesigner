import SwiftData
import SwiftUI

/// One room: the newest picture of it, the photos it was scanned with, and the
/// one thing worth doing next.
struct RoomDetailView: View {
    @Bindable var room: ScannedRoom

    @ObservedObject private var accents = RoomAccents.shared

    @State private var heroImage: UIImage?
    @State private var opened: RoomPicture?
    @State private var isShowingGallery = false
    @State private var isShowingPhotos = false
    @State private var isDesigning = false
    @State private var isLayingOut = false

    private var accent: Color { accents.accent(for: room) }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            if room.capturedRoom == nil {
                unscanned
            } else {
                content
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isShowingGallery = true } label: {
                        Label("All pictures", systemImage: "square.grid.2x2")
                    }
                    .disabled(pictures.isEmpty)
                    Button { isShowingPhotos = true } label: {
                        Label("Photos of the room", systemImage: "camera")
                    }
                    .disabled(room.sortedPhotos.isEmpty)
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Paper.ink)
                }
            }
        }
        .tint(accent)
        .environment(\.roomAccent, accent)
        .task { await accents.load(room) }
        .task(id: hero?.id) { await loadHero() }
        .fullScreenCover(item: $opened) { picture in
            PictureDetailView(picture: picture, onDelete: { delete(picture) })
        }
        .fullScreenCover(isPresented: $isShowingGallery) {
            PictureGalleryView(room: room)
        }
        .fullScreenCover(isPresented: $isShowingPhotos) {
            ScanPhotosView(room: room)
        }
        .fullScreenCover(isPresented: $isDesigning) {
            DesignFlowView(room: room)
        }
        .navigationDestination(isPresented: $isLayingOut) {
            LayoutView(room: room)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            hero.map { heroCard($0) } ?? AnyView(emptyHero)
            photoStrip
            counts
            Spacer(minLength: 12)
            actions
        }
    }

    private var unscanned: some View {
        ContentUnavailableView {
            Label("Nothing scanned", systemImage: "questionmark")
        } description: {
            Text("This room has no scan, so there is nothing to design from.")
        }
    }

    // MARK: - The newest picture

    /// Newest first, with the pictures the retired one-shot flow left behind
    /// after them, so an old room still shows what it has.
    private var pictures: [RoomPicture] {
        room.sortedPictures.map { RoomPicture.made($0) }
            + room.conceptImages.enumerated().reversed().map { RoomPicture.concept(index: $0, data: $1) }
    }

    private var hero: RoomPicture? { pictures.first }

    private func heroCard(_ picture: RoomPicture) -> AnyView {
        AnyView(
            Button { opened = picture } label: {
                ZStack(alignment: .bottomLeading) {
                    FilledImage(image: heroImage)
                        .frame(height: 430)
                        .frame(maxWidth: .infinity)

                    LinearGradient(colors: [Color(red: 0.11, green: 0.098, blue: 0.09).opacity(0.72),
                                            .clear],
                                   startPoint: .bottom, endPoint: .top)
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(picture.prompt)
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            ForEach(Array(picture.markers.enumerated()), id: \.offset) { _, marker in
                                MarkerDot(marker: marker, size: 9)
                            }
                            Text(picture.caption)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.bottom, 14)
                }
                .frame(height: 430)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Newest picture. \(picture.prompt)")
        )
    }

    private var emptyHero: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("No pictures yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Paper.ink)
            Text("Design makes one from a photo of this room.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 430)
        .background(Paper.tint)
    }

    private func loadHero() async {
        guard let data = hero?.fullData else { return heroImage = nil }
        heroImage = await Task.detached(priority: .userInitiated) {
            LibraryImage.thumbnail(from: data, maxPixelSize: 1400)
        }.value
    }

    private func delete(_ picture: RoomPicture) {
        opened = nil
        switch picture {
        case .made(let made):
            room.pictures = (room.pictures ?? []).filter { $0 !== made }
            RoomPicture.modelContext(of: made)?.delete(made)
        case .concept(let index, _):
            // A fresh array, never a removal in place: SwiftData may not see one.
            var remaining = room.conceptImages
            guard remaining.indices.contains(index) else { return }
            remaining.remove(at: index)
            room.conceptImages = remaining
        }
    }

    // MARK: - Photos of the real room

    private var photoStrip: some View {
        let photos = room.sortedPhotos
        return HStack(spacing: 10) {
            if let first = photos.first {
                photoTile(first)
                if photos.count > 1 {
                    Button { isShowingPhotos = true } label: {
                        Text("+\(photos.count - 1) more")
                            .font(.system(size: 13))
                            .foregroundStyle(Paper.mutedInk)
                            .frame(width: 108, height: 84)
                            .background(Paper.deepTint,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { isShowingPhotos = true } label: {
                VStack(spacing: 5) {
                    Image(systemName: "camera").font(.system(size: 19, weight: .light))
                    Text(photos.isEmpty ? "No photos" : "Photos").font(.system(size: 12))
                }
                .foregroundStyle(Paper.mutedInk)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .background(Paper.tint,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(photos.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func photoTile(_ photo: ScanPhoto) -> some View {
        Button { isShowingPhotos = true } label: {
            FilledImage(image: photo.thumbnail)
                .frame(width: 108, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photos of the room")
    }

    private var counts: some View {
        Button { if !pictures.isEmpty { isShowingGallery = true } } label: {
            Text(countsText)
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var countsText: String {
        let photos = room.sortedPhotos.count
        let made = pictures.count
        let left = made == 1 ? "1 picture" : "\(made) pictures"
        let right = photos == 1 ? "1 photo of the real room" : "\(photos) photos of the real room"
        return "\(left) · \(right)"
    }

    // MARK: - The one action

    private var actions: some View {
        VStack(spacing: 10) {
            Button { isDesigning = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold))
                    Text("Design")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Layout") { isLayingOut = true }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 28)
    }
}

/// A picture of this room, however it was made.
enum RoomPicture: Identifiable {
    case made(GeneratedPicture)
    /// From the retired one-shot flow, kept so old rooms still show their work.
    case concept(index: Int, data: Data)

    var id: String {
        switch self {
        case .made(let picture): return "made-\(picture.persistentModelID.hashValue)"
        case .concept(let index, _): return "concept-\(index)"
        }
    }

    var prompt: String {
        switch self {
        case .made(let picture): return picture.prompt
        case .concept: return "An earlier design of this room"
        }
    }

    var markers: [Marker] {
        guard case .made(let picture) = self else { return [] }
        return picture.products.compactMap(\.marker)
    }

    var caption: String {
        switch self {
        case .made(let picture):
            let count = picture.products.count
            let products = count == 0 ? "Just the room" : (count == 1 ? "1 product" : "\(count) products")
            return "\(products) · from \(picture.angle.lowercased())"
        case .concept:
            return "From the scan"
        }
    }

    var fullData: Data? {
        switch self {
        case .made(let picture): return picture.imageData
        case .concept(_, let data): return data
        }
    }

    var thumbnailData: Data? {
        switch self {
        case .made(let picture): return picture.thumbnailData ?? picture.imageData
        case .concept(_, let data): return data
        }
    }

    static func modelContext(of picture: GeneratedPicture) -> ModelContext? {
        picture.modelContext
    }
}
