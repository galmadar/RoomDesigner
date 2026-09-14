import SwiftData
import SwiftUI

/// Every picture of one room, newest first.
struct PictureGalleryView: View {
    let room: ScannedRoom

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var jobs = PictureJobs.shared
    @State private var opened: RoomPicture?
    @State private var doomed: RoomPicture?

    private var pictures: [RoomPicture] {
        room.sortedPictures.map { RoomPicture.made($0) }
            + room.conceptImages.enumerated().reversed().map { RoomPicture.concept(index: $0, data: $1) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Paper.sheet.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        // Being made comes before made: the grid stays newest first.
                        ForEach(jobs.jobs(for: room)) { job in
                            MakingPictureTile(job: job)
                                .aspectRatio(1, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(pictures) { picture in
                            Button { opened = picture } label: { tile(picture) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(16)

                    Text("Tap a picture to see it full screen, share it or delete it.")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Pictures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Deleted only once the cover is gone: reading a deleted model's properties traps.
        .fullScreenCover(item: $opened, onDismiss: deleteDoomed) { picture in
            PictureDetailView(picture: picture) { doomed = picture; opened = nil }
        }
    }

    private func tile(_ picture: RoomPicture) -> some View {
        PictureThumbnail(data: picture.thumbnailData)
            .aspectRatio(1, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// A fresh array rather than a removal in place, which SwiftData may not see.
    private func deleteDoomed() {
        guard let doomed else { return }
        switch doomed {
        case .made(let picture):
            room.pictures = (room.pictures ?? []).filter { $0 !== picture }
            context.delete(picture)
            try? context.save()
        case .concept(let index, _):
            var remaining = room.conceptImages
            if remaining.indices.contains(index) { remaining.remove(at: index) }
            room.conceptImages = remaining
        }
        self.doomed = nil
    }
}

/// A picture's thumbnail, decoded off the main thread.
struct PictureThumbnail: View {
    let data: Data?
    var maxPixelSize: CGFloat = 500

    @State private var image: UIImage?

    var body: some View {
        FilledImage(image: image)
            .task(id: data) {
                guard let data else { return image = nil }
                let size = maxPixelSize
                image = await Task.detached(priority: .userInitiated) {
                    LibraryImage.thumbnail(from: data, maxPixelSize: size)
                }.value
            }
    }
}

/// One picture full screen, with everything that made it.
struct PictureDetailView: View {
    let picture: RoomPicture
    /// Which room it was made for, where the screen it was opened from knows.
    /// Nil from inside a room, which is already titled with its name.
    var roomName: String? = nil
    /// Nil where deleting makes no sense, such as straight after making it.
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isConfirmingDelete = false

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
            // Cutting across rooms, which room this is of is the one thing the
            // screen cannot otherwise say.
            .navigationTitle(roomName ?? "Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("Room design", image: Image(uiImage: image)))
                    }
                    if onDelete != nil {
                        Button(role: .destructive) { isConfirmingDelete = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .confirmationDialog("Delete this picture?", isPresented: $isConfirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete?() }
            } message: {
                Text("It will be removed from this room.")
            }
            .task {
                guard let data = picture.fullData else { return }
                image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
            }
        }
    }

    @ViewBuilder private var details: some View {
        if case .made(let made) = picture {
            VStack(alignment: .leading, spacing: 14) {
                detail("What you asked for") { Text(made.prompt) }
                detail("Made with") {
                    Text("\(made.modelName), \(made.createdAt.formatted(date: .abbreviated, time: .shortened))")
                }
                detail("Angle") {
                    HStack(spacing: 10) {
                        if let data = made.sourcePhotoData, let photo = UIImage(data: data) {
                            FilledImage(image: photo)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        Text(angleDescription(made))
                    }
                }
                detail("Products") {
                    let products = made.products
                    if products.isEmpty {
                        Text("Nothing new — the room was restyled as it stands.")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(products.enumerated()), id: \.offset) { _, product in
                                HStack(spacing: 8) {
                                    MarkerDot(marker: product.marker)
                                    Text(product.name)
                                    Text(product.marker.map { "\($0.rawValue) box" } ?? "not placed")
                                        .foregroundStyle(Paper.secondaryInk)
                                }
                            }
                        }
                    }
                }
                if let data = made.scanRenderData, let render = UIImage(data: data) {
                    detail("What the model was shown") {
                        Image(uiImage: render).resizable().scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(Paper.ink)
        } else {
            Text("Made by an earlier version of the app, from the scan alone.")
                .font(.subheadline)
                .foregroundStyle(Paper.secondaryInk)
        }
    }

    private func angleDescription(_ made: GeneratedPicture) -> String {
        let hasPhoto = made.sourcePhotoData != nil
        if made.angle.hasPrefix("Photo") { return "From \(made.angle.lowercased())" }
        return hasPhoto ? "Any angle, with a photo taken nearby" : "Any angle, no room photo"
    }

    private func detail<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Paper.secondaryInk)
            content()
        }
    }
}
