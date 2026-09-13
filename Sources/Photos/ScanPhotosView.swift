import SwiftData
import SwiftUI

/// The photos taken while the room was scanned; tapping one checks it against the scan.
struct ScanPhotosView: View {
    let room: ScannedRoom

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var opened: ScanPhoto?

    var body: some View {
        NavigationStack {
            ZStack {
                Paper.sheet.ignoresSafeArea()
                let photos = room.sortedPhotos
                if photos.isEmpty {
                    empty
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(Array(photos.enumerated()), id: \.element.persistentModelID) { index, photo in
                                tile(photo, number: index + 1)
                            }
                        }
                        .padding(16)

                        Text("Tap a photo to check it lines up with the scan. Long-press to delete.")
                            .font(.system(size: 13))
                            .foregroundStyle(Paper.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                }
            }
        }
        .fullScreenCover(item: $opened) { PhotoAlignmentView(photo: $0, room: room) }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("No photos of\nthis room")
                .question()
                .multilineTextAlignment(.center)
            Text("Photos are taken while a room is scanned. This one was scanned without them, so pictures of it are drawn from the scan alone.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private func tile(_ photo: ScanPhoto, number: Int) -> some View {
        FilledImage(image: photo.thumbnail)
        .frame(height: 186)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Numbered as the floor plan's photo spots are.
        .overlay(alignment: .topTrailing) {
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.55), in: Circle())
                .padding(9)
        }
        .onTapGesture { opened = photo }
        .contextMenu {
            Button(role: .destructive) { remove(photo) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// A fresh array rather than a removal in place, which SwiftData may not see.
    private func remove(_ photo: ScanPhoto) {
        room.photos = (room.photos ?? []).filter { $0 !== photo }
        context.delete(photo)
    }
}
