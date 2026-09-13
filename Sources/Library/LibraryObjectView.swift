import SwiftData
import SwiftUI

struct LibraryObjectView: View {
    @Bindable var object: LibraryObject

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ObjectPictures(object: object)
                details
                if let url = object.sourceURL {
                    Link(destination: url) {
                        Label("Open on \(Self.siteName(of: url))", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button(role: .destructive) { isConfirmingDelete = true } label: {
                    Label("Delete from library", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(object.name.isEmpty ? "Untitled" : object.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this from the library?", isPresented: $isConfirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { isDeleting = true; dismiss() }
        } message: {
            Text("It won't be available in any room after this.")
        }
        // Deleted only once off screen: reading a deleted model's properties traps.
        .onDisappear {
            if isDeleting {
                context.delete(object)
                try? context.save()
            } else if object.name.trimmingCharacters(in: .whitespaces).isEmpty {
                object.name = "Untitled"
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.headline)
                TextField("Name", text: $object.name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Kind").font(.headline)
                    Spacer()
                    KindPicker(kind: Binding(get: { object.furnitureKind },
                                             set: { object.furnitureKind = $0 }))
                }
                Text(KindPicker.explanation).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private static func siteName(of url: URL) -> String {
        guard let host = url.host() else { return "the shop's site" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Its own view so typing the name doesn't re-decode every picture.
private struct ObjectPictures: View {
    let object: LibraryObject

    private struct Enlarged: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    @State private var pictures: [UIImage] = []
    @State private var page = 0
    @State private var enlarged: Enlarged?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabView(selection: $page) {
                ForEach(pictures.indices, id: \.self) { index in
                    Image(uiImage: pictures[index])
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { enlarged = Enlarged(image: pictures[index]) }
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 340)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if pictures.count > 1 { strip }

            HStack(spacing: 8) {
                if page == 0 {
                    Label("Main picture", systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button { makeMain(page) } label: {
                        Label("Make this the main picture", systemImage: "star")
                    }
                }
                Spacer()
                if pictures.count > 1 {
                    Button(role: .destructive) { remove(page) } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Remove this picture")
                }
            }
            .buttonStyle(.bordered)

            Text("The main picture is the one used when designing a room.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: object.imagesData) {
            pictures = await LibraryImage.thumbnails(for: object.imagesData, maxPixelSize: 1200)
            page = min(page, max(pictures.count - 1, 0))
        }
        .fullScreenCover(item: $enlarged) { enlarged in
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: enlarged.image).resizable().scaledToFit()
            }
            .onTapGesture { self.enlarged = nil }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pictures.indices, id: \.self) { index in
                    Button { withAnimation { page = index } } label: {
                        Image(uiImage: pictures[index])
                            .resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(index == page ? Color.accentColor : .clear, lineWidth: 2)
                            }
                            .overlay(alignment: .topLeading) {
                                if index == 0 {
                                    Image(systemName: "star.fill")
                                        .font(.caption2).foregroundStyle(.yellow)
                                        .shadow(radius: 1).padding(3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Picture \(index + 1)")
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // Both write a fresh array: SwiftData doesn't observe in-place mutation of a stored collection.

    private func makeMain(_ index: Int) {
        var images = object.imagesData
        guard images.indices.contains(index) else { return }
        let chosen = images.remove(at: index)
        object.imagesData = [chosen] + images
        var shown = pictures
        let picture = shown.remove(at: index)
        pictures = [picture] + shown
        page = 0
    }

    private func remove(_ index: Int) {
        guard object.imagesData.count > 1, object.imagesData.indices.contains(index) else { return }
        object.imagesData = object.imagesData.enumerated().filter { $0.offset != index }.map(\.element)
        pictures = pictures.enumerated().filter { $0.offset != index }.map(\.element)
        page = min(page, pictures.count - 1)
    }
}

/// Which proxy shape the object takes on a floor plan.
struct KindPicker: View {
    @Binding var kind: Furniture.Kind?

    static let explanation = "The shape it takes when you place it on a floor plan. Leave it unset for things without one here, like a painting or a mirror."

    var body: some View {
        Picker("Kind", selection: $kind) {
            Text("Not set").tag(Furniture.Kind?.none)
            ForEach(Furniture.Kind.allCases) { kind in
                Label(kind.label, systemImage: kind.symbol).tag(Furniture.Kind?.some(kind))
            }
        }
        .pickerStyle(.menu)
    }
}
