import SwiftData
import SwiftUI

/// Every photo of this room — taken while scanning or added from the camera
/// roll. Tapping one checks it against the scan, or, if it has no place in the
/// room yet, offers to give it one.
struct ScanPhotosView: View {
    let room: ScannedRoom

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.roomAccent) private var accent
    @State private var opened: ScanPhoto?
    @State private var placing: ScanPhoto?
    @State private var isAdding = false

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

                        Text(hint)
                            .font(.system(size: 13))
                            .foregroundStyle(Paper.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button { isAdding = true } label: {
                        Image(systemName: "photo.badge.plus").foregroundStyle(Paper.ink)
                    }
                    .accessibilityLabel("Add a photo from your library")
                }
            }
        }
        .tint(accent)
        .roomPhotoPicker(room: room, isPresented: $isAdding) { placing = $0 }
        .fullScreenCover(item: $opened) { PhotoAlignmentView(photo: $0, room: room) }
        .fullScreenCover(item: $placing) { PhotoPlaceFlow(room: room, photo: $0) }
    }

    private var hint: String {
        var said = ["Tap a photo to check it lines up with the scan. Long-press to delete."]
        if room.sortedPhotos.contains(where: { !$0.isPlaced }) {
            said.append("The dashed ones have no place in the room yet — tap one to give it a spot, or leave it as it is.")
        }
        return said.joined(separator: " ")
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("No photos of\nthis room")
                .question()
                .multilineTextAlignment(.center)
            Text("Photos are taken while a room is scanned. This one was scanned without them — but you can add one from your library and say where it was taken from.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
            Button("Add a photo") { isAdding = true }
                .buttonStyle(QuietButtonStyle())
                .padding(.horizontal, 60)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private func tile(_ photo: ScanPhoto, number: Int) -> some View {
        FilledImage(image: photo.thumbnail)
        .frame(height: 186)
        .frame(maxWidth: .infinity)
        .opacity(photo.isPlaced ? 1 : 0.55)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Dashed where there is no spot, so the grid says which is which before
        // anything is tapped.
        .overlay {
            if !photo.isPlaced {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Paper.outline, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        // Numbered as the floor plan's photo spots are.
        .overlay(alignment: .topTrailing) {
            Group {
                if photo.isPlaced {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.black.opacity(0.55), in: Circle())
            .padding(9)
        }
        .onTapGesture { if photo.isPlaced { opened = photo } else { placing = photo } }
        .contextMenu {
            Button { placing = photo } label: {
                Label(photo.isPlaced ? "Move it" : "Place it", systemImage: "mappin.and.ellipse")
            }
            Button(role: .destructive) { remove(photo) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(photo.isPlaced
                            ? "Photo \(number). \(photo.caption)"
                            : "A photo with no place in the room. \(photo.caption)")
    }

    /// A fresh array rather than a removal in place, which SwiftData may not see.
    private func remove(_ photo: ScanPhoto) {
        room.photos = (room.photos ?? []).filter { $0 !== photo }
        context.delete(photo)
    }
}
