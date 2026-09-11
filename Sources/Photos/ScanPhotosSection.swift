import SwiftData
import SwiftUI

/// The room's scan photos as a strip; tapping one checks it against the scan.
struct ScanPhotosSection: View {
    let room: ScannedRoom

    @Environment(\.modelContext) private var context
    @State private var opened: ScanPhoto?

    var body: some View {
        let photos = room.sortedPhotos
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("^[\(photos.count) photo](inflect: true)").font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            thumbnail(photo)
                                .onTapGesture { opened = photo }
                                .contextMenu {
                                    Button(role: .destructive) { remove(photo) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 1)
                }

                Text("Tap a photo to check it lines up with the scan. Long-press to delete.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .fullScreenCover(item: $opened) { PhotoAlignmentView(photo: $0, room: room) }
        }
    }

    private func thumbnail(_ photo: ScanPhoto) -> some View {
        Group {
            if let image = photo.thumbnail {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(.secondarySystemBackground)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    /// A fresh array rather than a removal in place, which SwiftData may not see.
    private func remove(_ photo: ScanPhoto) {
        room.photos = (room.photos ?? []).filter { $0 !== photo }
        context.delete(photo)
    }
}
