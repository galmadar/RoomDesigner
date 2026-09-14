import SwiftData
import SwiftUI

/// A value rather than a view, so the room list's `NavigationPath` can hold it.
struct GalleryRoute: Hashable {}

/// Everything the app has made, from every room at once, next to the
/// photographs the rooms were scanned from.
///
/// A room already shows its own pictures; the only reason this screen exists is
/// to cut across rooms, so it does not group by room — that would put back the
/// wall it is here to take down. It groups by month instead, because what the
/// user is looking for in a hundred pictures is nearly always "the one from
/// around then", and because a month heading costs no control.
struct GalleryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScannedRoom.createdAt, order: .reverse) private var rooms: [ScannedRoom]

    @ObservedObject private var accents = RoomAccents.shared

    @State private var months: [GalleryMonth] = []
    @State private var opened: GalleryItem?
    @State private var doomed: GalleryItem?
    @State private var hasAutoOpened = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    /// What a rebuild depends on, without touching the stored image blobs.
    private var signature: String {
        let pictures = rooms.reduce(0) { $0 + ($1.pictures ?? []).count }
        let photos = rooms.reduce(0) { $0 + ($1.photos ?? []).count }
        return "\(rooms.count)-\(pictures)-\(photos)"
    }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            if months.isEmpty { empty } else { grid }
        }
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .task(id: signature) { rebuild() }
        .task(id: signature) { for room in rooms { await accents.load(room) } }
        // Deleted only once the cover is gone: reading a deleted model's properties traps.
        .fullScreenCover(item: $opened, onDismiss: deleteDoomed) { item in
            switch item {
            case .design(let picture, _, _):
                PictureDetailView(picture: picture) { doomed = item; opened = nil }
            case .photograph(let photo, let room):
                GalleryPhotoView(photo: photo, room: room) { doomed = item; opened = nil }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            // Said once, at the top: this is the only screen in the app that
            // mixes what was designed with what is actually there.
            Text("Everything you have designed, newest first, with the photographs your rooms were scanned from. Photographs are marked.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 8, pinnedViews: [.sectionHeaders]) {
                ForEach(months) { month in
                    Section {
                        ForEach(month.items) { item in
                            Button { opened = item } label: {
                                GalleryTile(item: item, accent: accents.accent(for: item.room))
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        header(month.title)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Paper.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .background(Paper.sheet)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("Nothing here yet")
                .question()
                .multilineTextAlignment(.center)
            Text("Every picture you design lands here, beside the photographs its room was scanned from. All your rooms at once, newest first.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    // MARK: -

    private func rebuild() {
        let calendar = Calendar.current
        var items: [GalleryItem] = []
        for room in rooms {
            for picture in room.sortedPictures {
                items.append(.design(.made(picture), room: room, madeAt: picture.createdAt))
            }
            // The retired one-shot flow kept no date, so these sit with their room.
            for (index, data) in room.conceptImages.enumerated() {
                items.append(.design(.concept(index: index, data: data), room: room,
                                     madeAt: room.createdAt))
            }
            for photo in room.sortedPhotos {
                items.append(.photograph(photo, room: room))
            }
        }
        items.sort { $0.date > $1.date }

        var grouped: [Date: [GalleryItem]] = [:]
        for item in items {
            let start = calendar.dateInterval(of: .month, for: item.date)?.start ?? item.date
            grouped[start, default: []].append(item)
        }
        months = grouped.keys.sorted(by: >).map {
            GalleryMonth(id: $0, title: $0.formatted(.dateTime.month(.wide).year()),
                         items: grouped[$0] ?? [])
        }
        autoOpenIfAsked()
    }

    /// A simulator cannot be tapped from a script, so the cover under test is
    /// opened by name. Once only, or dismissing it would reopen it.
    private func autoOpenIfAsked() {
        guard !hasAutoOpened, let wanted = GallerySeed.opensItem else { return }
        let all = months.flatMap(\.items)
        opened = wanted == "photo"
            ? all.first(where: \.isPhotograph)
            : all.first(where: { !$0.isPhotograph })
        hasAutoOpened = opened != nil
    }

    /// A fresh array rather than a removal in place, which SwiftData may not see.
    private func deleteDoomed() {
        guard let doomed else { return }
        switch doomed {
        case .design(let picture, let room, _):
            switch picture {
            case .made(let made):
                room.pictures = (room.pictures ?? []).filter { $0 !== made }
                context.delete(made)
            case .concept(let index, _):
                var remaining = room.conceptImages
                if remaining.indices.contains(index) { remaining.remove(at: index) }
                room.conceptImages = remaining
            }
        case .photograph(let photo, let room):
            room.photos = (room.photos ?? []).filter { $0 !== photo }
            context.delete(photo)
        }
        try? context.save()
        self.doomed = nil
        rebuild()
    }
}

// MARK: - What is in the gallery

/// One thing in the gallery, and the room it came out of.
///
/// The room travels with the item rather than being looked up later, so a
/// picture opened from here still knows where it belongs and a delete reaches
/// the right room's relationship.
enum GalleryItem: Identifiable {
    case design(RoomPicture, room: ScannedRoom, madeAt: Date)
    case photograph(ScanPhoto, room: ScannedRoom)

    /// Concept ids repeat across rooms, so the room is part of the identity.
    var id: String {
        switch self {
        case .design(let picture, let room, _):
            return "d\(room.persistentModelID.hashValue)-\(picture.id)"
        case .photograph(let photo, _):
            return "p\(photo.persistentModelID.hashValue)"
        }
    }

    var room: ScannedRoom {
        switch self {
        case .design(_, let room, _): return room
        case .photograph(_, let room): return room
        }
    }

    var date: Date {
        switch self {
        case .design(_, _, let madeAt): return madeAt
        case .photograph(let photo, _): return photo.takenAt
        }
    }

    var isPhotograph: Bool {
        if case .photograph = self { return true }
        return false
    }

    var thumbnailData: Data? {
        switch self {
        case .design(let picture, _, _): return picture.thumbnailData
        case .photograph(let photo, _): return photo.thumbnailData ?? photo.imageData
        }
    }

    var spokenLabel: String {
        let day = date.formatted(date: .abbreviated, time: .omitted)
        return isPhotograph
            ? "Photograph of \(room.name), \(day)"
            : "Design for \(room.name), \(day)"
    }
}

struct GalleryMonth: Identifiable {
    let id: Date
    let title: String
    let items: [GalleryItem]
}

// MARK: - One tile

/// A picture in the grid, saying which room it came from and — where it matters
/// — that it is not a design at all.
///
/// A generated picture and a photograph of the real room are the same thing at
/// this size, and taking one for the other is the only mistake this screen can
/// cause. So a photograph is labelled in words on a bar across its foot, which
/// survives being 115 pt wide in a way a corner glyph does not. A design carries
/// no badge: on a screen called Gallery, made by the app is the ordinary case.
private struct GalleryTile: View {
    let item: GalleryItem
    let accent: Color

    var body: some View {
        GalleryThumbnail(key: item.id, data: item.thumbnailData)
            .aspectRatio(1, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    if item.isPhotograph { photographBar }
                    // The room's own colour, the way its card in the list wears it.
                    accent.frame(height: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel(item.spokenLabel)
    }

    private var photographBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "camera.fill").font(.system(size: 9, weight: .semibold))
            Text("Photo").font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.62))
    }
}

/// A tile's picture, decoded small and off the main thread, and kept in one
/// bounded cache rather than on the tile.
struct GalleryThumbnail: View {
    let key: String
    let data: Data?
    var maxPixelSize = GalleryThumbnails.tilePixels

    @State private var image: UIImage?

    init(key: String, data: Data?, maxPixelSize: CGFloat = GalleryThumbnails.tilePixels) {
        self.key = key
        self.data = data
        self.maxPixelSize = maxPixelSize
        // Scrolling back to a tile already decoded should not flash empty.
        _image = State(initialValue: GalleryThumbnails.shared.cached(key))
    }

    var body: some View {
        FilledImage(image: image)
            .task(id: key) {
                if let hit = GalleryThumbnails.shared.cached(key) { return image = hit }
                guard let data else { return image = nil }
                image = await GalleryThumbnails.shared.image(for: key, data: data,
                                                             maxPixelSize: maxPixelSize)
            }
    }
}
