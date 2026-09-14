import SwiftUI

/// One photograph of a real room, full screen.
///
/// `PictureDetailView` is the same screen for something the app made, and this
/// is deliberately its twin: the same chrome, the same share, the same delete.
/// It is separate because everything it says underneath is different — a
/// photograph has no prompt and no model, it has a room and a day.
struct GalleryPhotoView: View {
    let photo: ScanPhoto
    let room: ScannedRoom
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isConfirmingDelete = false
    @State private var isCheckingScan = false

    /// Only a photo taken during a scan knows where it was taken from. One
    /// brought in any other way has nothing to line up against the room.
    private var canCheckScan: Bool {
        photo.viewpoint != nil && room.capturedRoom != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Paper.sheet.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Group {
                            if let image {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 280)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        details
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("Room photo", image: Image(uiImage: image)))
                    }
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $isConfirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete() }
            } message: {
                Text("It will be removed from \(room.name), and pictures can no longer be designed from this angle.")
            }
            .fullScreenCover(isPresented: $isCheckingScan) {
                PhotoAlignmentView(photo: photo, room: room)
            }
            .task {
                let data = photo.imageData
                image = await Task.detached(priority: .userInitiated) {
                    LibraryImage.thumbnail(from: data, maxPixelSize: 2000)
                }.value
            }
        }
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            detail("What this is") {
                Text("A photograph of \(room.name) as it really is, not a design.")
            }
            detail("Taken") {
                Text(photo.takenAt.formatted(date: .long, time: .shortened))
            }
            if canCheckScan {
                Button("Check it against the scan") { isCheckingScan = true }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .font(.subheadline)
        .foregroundStyle(Paper.ink)
    }

    private func detail<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Paper.secondaryInk)
            content()
        }
    }
}
