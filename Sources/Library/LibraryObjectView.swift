import SwiftData
import SwiftUI

struct LibraryObjectView: View {
    @Bindable var object: LibraryObject

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ObjectPictures(object: object)
                    details
                    if let url = object.sourceURL {
                        Link(destination: url) {
                            quietLabel("Open on \(Self.siteName(of: url))", symbol: "safari")
                        }
                    }
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        quietLabel("Delete from library", symbol: "trash", tint: Paper.destructive)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(object.name.isEmpty ? "Untitled" : object.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
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

    private func quietLabel(_ title: String, symbol: String,
                            tint: Color = Paper.quietInk) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15))
            Text(title).font(.system(size: 16))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Paper.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Name")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                TextField("Name", text: $object.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(Paper.ink)
                    .submitLabel(.done)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .paperCard(radius: 14)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Kind")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                    Spacer()
                    KindPicker(kind: Binding(get: { object.furnitureKind },
                                             set: { object.furnitureKind = $0 }))
                }
                Text(KindPicker.explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
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

    @Environment(\.roomAccent) private var accent

    @State private var pictures: [UIImage] = []
    @State private var page = 0
    @State private var enlarged: Enlarged?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabView(selection: $page) {
                ForEach(pictures.indices, id: \.self) { index in
                    Image(uiImage: pictures[index])
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                        .contentShape(Rectangle())
                        .onTapGesture { enlarged = Enlarged(image: pictures[index]) }
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 340)
            .background(Paper.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Paper.cardShadow, radius: 1.5, x: 0, y: 1)

            if pictures.count > 1 { strip }

            HStack(spacing: 10) {
                if page == 0 {
                    HStack(spacing: 7) {
                        Image(systemName: "star.fill").font(.system(size: 13))
                        Text("Main picture").font(.system(size: 14))
                    }
                    .foregroundStyle(Paper.secondaryInk)
                    .frame(minHeight: 44)
                } else {
                    Button { makeMain(page) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "star").font(.system(size: 14))
                            Text("Make this the main picture").font(.system(size: 15))
                        }
                        .foregroundStyle(Paper.quietInk)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Paper.tint,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if pictures.count > 1 {
                    Button(role: .destructive) { remove(page) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(Paper.destructive)
                            .frame(width: 44, height: 44)
                            .background(Paper.tint,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this picture")
                }
            }

            Text("The main picture is the one used when designing a room.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
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
                        FilledImage(image: pictures[index])
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(index == page ? accent : .clear, lineWidth: 2.5)
                            }
                            .overlay(alignment: .topLeading) {
                                if index == 0 {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(accent, in: Circle())
                                        .padding(3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Picture \(index + 1)")
                }
            }
            .padding(.horizontal, 2)
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
        .font(.system(size: 16))
        .tint(Paper.quietInk)
    }
}
