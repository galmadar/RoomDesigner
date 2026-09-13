import SwiftData
import SwiftUI

/// The room's pictures from "Design with photos", newest first.
struct PictureCollectionSection: View {
    let room: ScannedRoom

    @Environment(\.modelContext) private var context
    @State private var opened: GeneratedPicture?
    @State private var doomed: GeneratedPicture?

    var body: some View {
        let pictures = room.sortedPictures
        if !pictures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("^[\(pictures.count) picture](inflect: true) with your products")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(pictures.enumerated()), id: \.element.persistentModelID) { index, picture in
                        Button { opened = picture } label: { tile(picture) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Picture \(index + 1)")
                    }
                }
                Text("Tap a picture to see it full screen, share it or delete it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            // Deleted only once the cover is gone: reading a deleted model's properties traps.
            .fullScreenCover(item: $opened, onDismiss: deleteDoomed) { picture in
                PictureDetailView(picture: picture) { doomed = picture; opened = nil }
            }
        }
    }

    private func tile(_ picture: GeneratedPicture) -> some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail = picture.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    /// A fresh array rather than a removal in place, which SwiftData may not see.
    private func deleteDoomed() {
        guard let doomed else { return }
        room.pictures = (room.pictures ?? []).filter { $0 !== doomed }
        context.delete(doomed)
        try? context.save()
        self.doomed = nil
    }
}

/// One picture full screen, with everything that made it.
struct PictureDetailView: View {
    let picture: GeneratedPicture
    /// Nil where deleting makes no sense, such as straight after making it.
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 280)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    details
                }
                .padding()
            }
            .navigationTitle("Picture")
            .navigationBarTitleDisplayMode(.inline)
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
                let data = picture.imageData
                image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            detail("What you asked for") { Text(picture.prompt) }
            detail("Made with") {
                Text("\(picture.modelName), \(picture.createdAt.formatted(date: .abbreviated, time: .shortened))")
            }
            detail("Angle") {
                HStack(spacing: 10) {
                    if let data = picture.sourcePhotoData, let photo = UIImage(data: data) {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text(angleDescription)
                }
            }
            detail("Products") {
                let products = picture.products
                if products.isEmpty {
                    Text("None")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(products.enumerated()), id: \.offset) { _, product in
                            HStack(spacing: 8) {
                                MarkerSwatch(marker: product.marker)
                                Text(product.name)
                                Text(product.marker.map { "\($0.rawValue) box" } ?? "not placed")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let data = picture.scanRenderData, let render = UIImage(data: data) {
                detail("What the model was shown") {
                    Image(uiImage: render).resizable().scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .font(.subheadline)
    }

    private var angleDescription: String {
        let hasPhoto = picture.sourcePhotoData != nil
        if picture.angle.hasPrefix("Photo") { return "From \(picture.angle.lowercased())" }
        return hasPhoto ? "Free angle, with a photo taken nearby" : "Free angle, no room photo"
    }

    private func detail<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

/// A product's box colour; a dashed outline when it wasn't placed.
struct MarkerSwatch: View {
    let marker: Marker?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(marker?.color ?? .clear)
            .overlay {
                if marker == nil {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

extension Marker {
    var color: Color { Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)) }
}
