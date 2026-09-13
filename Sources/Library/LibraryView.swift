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
        ZStack {
            Paper.sheet.ignoresSafeArea()
            if objects.isEmpty { empty } else { grid }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .navigationDestination(for: LibraryObject.self) { LibraryObjectView(object: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { addition = .link } label: { Label("Paste a link", systemImage: "link") }
                    Button { isPickingPhotos = true } label: {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Image(systemName: "plus").foregroundStyle(Paper.ink)
                }
                .accessibilityLabel("Add")
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
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Image(systemName: "sofa")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("Nothing saved yet")
                .question()
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Text("Found a sofa, a lamp or a painting you like? Paste its link from the shop, or choose photos of it. Everything here is shared by all your rooms.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .padding(.top, 8)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button { addition = .link } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "link").font(.system(size: 17, weight: .semibold))
                        Text("Paste a link")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Choose from Photos") { isPickingPhotos = true }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(objects) { object in
                    NavigationLink(value: object) { LibraryTile(object: object) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text("Shared by all your rooms.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
        }
    }
}

private struct LibraryTile: View {
    let object: LibraryObject
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FilledImage(image: thumbnail, symbol: "photo")
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)

            Text(object.name)
                .font(.system(size: 14))
                .foregroundStyle(Paper.ink)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .paperCard(radius: 16)
        .contentShape(Rectangle())
        .task(id: object.mainImageData) {
            guard let data = object.mainImageData else { return thumbnail = nil }
            thumbnail = await LibraryImage.thumbnails(for: [data], maxPixelSize: 500).first
        }
    }
}
