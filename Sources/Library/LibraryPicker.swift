import SwiftData
import SwiftUI

/// Chooses one product from the shared library.
struct LibraryPicker: View {
    let title: String
    let footnote: String
    /// Why a product can't be chosen here, or nil if it can.
    var unavailable: (LibraryObject) -> String? = { _ in nil }
    let onPick: (LibraryObject) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LibraryObject.createdAt, order: .reverse) private var objects: [LibraryObject]
    @StateObject private var thumbnails = ProductThumbnails()

    var body: some View {
        NavigationStack {
            Group {
                if objects.isEmpty {
                    ContentUnavailableView {
                        Label("Your library is empty", systemImage: "sofa")
                    } description: {
                        Text("Add products from the Library button on the Rooms screen, then come back here.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(objects) { row($0) }
                        } footer: {
                            Text(footnote)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: objects.map(\.id)) { await thumbnails.load(objects) }
        }
    }

    private func row(_ object: LibraryObject) -> some View {
        let reason = unavailable(object)
        return Button {
            onPick(object)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ProductThumbnail(image: thumbnails.images[object.id], size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(object.name).foregroundStyle(.primary).lineLimit(2)
                    Text(reason ?? object.furnitureKind?.label ?? "No floor shape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(reason != nil)
        .accessibilityLabel(object.name)
    }
}

/// A product's picture in a rounded square, or a placeholder while it loads.
struct ProductThumbnail: View {
    let image: UIImage?
    var size: CGFloat = 44

    var body: some View {
        Color(.secondarySystemBackground)
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
