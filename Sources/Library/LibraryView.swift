import PhotosUI
import SwiftData
import SwiftUI

/// A value rather than a view, so the room list's `NavigationPath` can hold it.
struct LibraryRoute: Hashable {}

/// Everything saved from shops, shared by all the rooms.
struct LibraryView: View {
    @Query(sort: \LibraryObject.createdAt, order: .reverse) private var objects: [LibraryObject]

    @State private var addition: LibraryAddition?
    @State private var isPickingPhotos = false
    @State private var pickedItems: [PhotosPickerItem] = []

    var body: some View {
        Group {
            if objects.isEmpty { empty } else { grid }
        }
        .navigationTitle("Library")
        .navigationDestination(for: LibraryObject.self) { LibraryObjectView(object: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { addition = .link } label: { Label("Paste a link", systemImage: "link") }
                    Button { isPickingPhotos = true } label: {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .photosPicker(isPresented: $isPickingPhotos, selection: $pickedItems,
                      maxSelectionCount: LibraryImage.maxPictures,
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: pickedItems) {
            guard !pickedItems.isEmpty else { return }
            addition = .photos(pickedItems)
            pickedItems = []
        }
        .sheet(item: $addition) { AddObjectView(addition: $0) }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing saved yet", systemImage: "sofa")
        } description: {
            Text("Found a sofa, a lamp or a painting you like? Paste its link from the shop, or choose photos of it. Everything here is shared by all your rooms.")
        } actions: {
            Button { addition = .link } label: { Label("Paste a link", systemImage: "link") }
                .buttonStyle(.borderedProminent)
            Button { isPickingPhotos = true } label: {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 18) {
                ForEach(objects) { object in
                    NavigationLink(value: object) { LibraryTile(object: object) }
                        .buttonStyle(.plain)
                }
            }
            .padding()

            Text("Shared by all your rooms.")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.bottom)
        }
    }
}

private struct LibraryTile: View {
    let object: LibraryObject
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(object.name)
                .font(.subheadline)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .contentShape(Rectangle())
        .task(id: object.mainImageData) {
            guard let data = object.mainImageData else { return thumbnail = nil }
            thumbnail = await LibraryImage.thumbnails(for: [data], maxPixelSize: 500).first
        }
    }
}
