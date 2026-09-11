import PhotosUI
import SwiftData
import SwiftUI

/// How an addition starts. Both roads end on the same picker, so keeping,
/// naming and saving work the same whichever way he came in.
enum LibraryAddition: Identifiable {
    case link
    case photos([PhotosPickerItem])

    var id: String {
        switch self {
        case .link: return "link"
        case .photos(let items): return "photos-\(items.hashValue)"
        }
    }
}

struct AddObjectView: View {
    let addition: LibraryAddition

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private enum Stage: Equatable {
        case enteringLink
        case working(String)
        case failed(String)
        case choosing
    }

    @State private var stage: Stage
    @State private var link = ""
    @State private var draft = ObjectDraft()
    @State private var hasBegun = false
    @State private var isPickingPhotos = false
    @State private var pickedItems: [PhotosPickerItem] = []

    init(addition: LibraryAddition) {
        self.addition = addition
        if case .link = addition {
            _stage = State(initialValue: .enteringLink)
        } else {
            _stage = State(initialValue: .working("Preparing photos…"))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .enteringLink:
                    linkForm
                case .working(let message):
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(message).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    failure(message)
                case .choosing:
                    DraftEditor(draft: $draft)
                }
            }
            .navigationTitle(stage == .choosing ? "Choose pictures" : "Add to library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if stage == .choosing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.disabled(draft.kept.isEmpty)
                    }
                }
            }
        }
        // Picked pictures are work; a stray swipe shouldn't throw them away.
        .interactiveDismissDisabled(stage == .choosing)
        .photosPicker(isPresented: $isPickingPhotos, selection: $pickedItems,
                      maxSelectionCount: LibraryImage.maxPictures,
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: pickedItems) {
            guard !pickedItems.isEmpty else { return }
            let items = pickedItems
            pickedItems = []
            Task { await loadPhotos(items) }
        }
        .task {
            guard !hasBegun else { return }
            hasBegun = true
            switch addition {
            case .link: await prefillFromClipboard()
            case .photos(let items): await loadPhotos(items)
            }
        }
    }

    // MARK: - Link

    private var linkForm: some View {
        Form {
            Section {
                TextField("https://", text: $link)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { Task { await findPictures() } }
            } header: {
                Text("Product link")
            } footer: {
                if !link.isEmpty && Self.webURL(in: link) == nil {
                    Text("That doesn't look like a web address. Copy the link from the product's page and paste it here.")
                } else {
                    Text("Copy the link from the product's page in Safari or the shop's app, then paste it here. You'll choose which pictures to keep.")
                }
            }

            Section {
                Button { Task { await findPictures() } } label: {
                    Text("Find pictures").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(Self.webURL(in: link) == nil)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    /// Checks the pattern first: that needs no permission, so the paste prompt
    /// only ever appears when there is actually a link to offer.
    private func prefillFromClipboard() async {
        let pasteboard = UIPasteboard.general
        guard link.isEmpty, pasteboard.hasURLs || pasteboard.hasStrings,
              let found = try? await pasteboard.detectedPatterns(for: [\.probableWebURL]),
              found.contains(\UIPasteboard.DetectedValues.probableWebURL)
        else { return }

        let text = pasteboard.hasURLs ? pasteboard.url?.absoluteString : pasteboard.string
        if link.isEmpty, let url = text.flatMap(Self.webURL(in:)) {
            link = url.absoluteString
        }
    }

    private func findPictures() async {
        guard let url = Self.webURL(in: link) else { return }
        stage = .working("Reading the page…")
        do {
            let found = try await PlanService().importObject(from: url)
            draft.sourceURL = url
            draft.source = found.source
            if let title = found.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                draft.name = title
                draft.kind = draft.kind ?? Self.guessKind(from: title)
            }

            let urls = Array(found.imageURLs.prefix(LibraryImage.maxPictures))
            guard !urls.isEmpty else {
                return stage = .failed("That page didn't have any pictures of the product.")
            }
            stage = .working(urls.count == 1 ? "Fetching the picture…" : "Fetching \(urls.count) pictures…")
            let jpegs = await LibraryImage.download(urls)
            guard !jpegs.isEmpty else {
                return stage = .failed("The product's pictures wouldn't download from the shop.")
            }
            await show(jpegs)
        } catch {
            stage = .failed(Self.message(for: error))
        }
    }

    // MARK: - Photos

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        stage = .working(items.count == 1 ? "Preparing the photo…" : "Preparing \(items.count) photos…")
        var jpegs: [Data] = []
        for item in items {
            guard let original = try? await item.loadTransferable(type: Data.self),
                  let jpeg = await LibraryImage.jpegInBackground(original)
            else { continue }
            jpegs.append(jpeg)
        }
        guard !jpegs.isEmpty else {
            return stage = .failed("Those photos couldn't be opened. Try choosing them again.")
        }
        await show(jpegs)
    }

    // MARK: - Shared

    private func show(_ jpegs: [Data]) async {
        let previews = await LibraryImage.thumbnails(for: jpegs, maxPixelSize: 500)
        draft.replacePictures(with: zip(jpegs, previews).map(ObjectDraft.Picture.init))
        stage = .choosing
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't add that", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if !link.isEmpty {
                Button("Try again") { Task { await findPictures() } }
                    .buttonStyle(.borderedProminent)
                Button("Change the link") { stage = .enteringLink }
                    .buttonStyle(.bordered)
            }
            Button {
                isPickingPhotos = true
            } label: {
                Label(link.isEmpty ? "Choose photos" : "Choose from Photos instead",
                      systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(LibraryObject(name: name.isEmpty ? "Untitled" : name,
                                     imagesData: draft.orderedJPEGs,
                                     sourceURL: draft.sourceURL,
                                     kind: draft.kind?.rawValue))
        // Saved at once: adding is deliberate, and a quit before autosave would lose it.
        try? context.save()
        dismiss()
    }

    /// The first web link anywhere in the text, since share sheets often copy
    /// "Product name – https://…" rather than the bare address.
    static func webURL(in text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .lazy.compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }

    private static func message(for error: Error) -> String {
        if let failure = error as? PlanService.ImportFailure {
            return failure.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The page took too long to load."
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You seem to be offline. Check your connection."
            default:
                return "Couldn't reach the design service."
            }
        }
        if error is DecodingError {
            return "The server's answer didn't make sense to this version of the app."
        }
        return error.localizedDescription
    }

    /// The last matching word wins: English puts the thing itself at the end,
    /// so a "table lamp" is a lamp and a "sofa table" is a table.
    static func guessKind(from title: String) -> Furniture.Kind? {
        let words: [String: Furniture.Kind] = [
            "sofa": .sofa, "couch": .sofa, "settee": .sofa, "loveseat": .sofa, "sectional": .sofa,
            "bed": .bed, "table": .table, "chair": .chair, "armchair": .chair, "stool": .chair,
            "desk": .desk, "wardrobe": .wardrobe, "armoire": .wardrobe, "closet": .wardrobe,
            "shelf": .shelf, "shelves": .shelf, "shelving": .shelf, "bookcase": .shelf,
            "bookshelf": .shelf, "rug": .rug, "carpet": .rug, "lamp": .lamp, "plant": .plant,
        ]
        let tokens = title.lowercased().split { !$0.isLetter }.map(String.init)
        for token in tokens.reversed() {
            if let kind = words[token] { return kind }
            if token.hasSuffix("s"), let kind = words[String(token.dropLast())] { return kind }
        }
        return nil
    }
}

/// The pictures on offer and what he's decided about them, before anything is saved.
struct ObjectDraft {
    struct Picture: Identifiable {
        let id = UUID()
        let jpeg: Data
        let preview: UIImage

        init(jpeg: Data, preview: UIImage) {
            self.jpeg = jpeg
            self.preview = preview
        }
    }

    var pictures: [Picture] = []
    var kept: Set<Picture.ID> = []
    var main: Picture.ID?
    var name = ""
    var kind: Furniture.Kind?
    var sourceURL: URL?
    var source: String?

    mutating func replacePictures(with pictures: [Picture]) {
        self.pictures = pictures
        kept = Set(pictures.map(\.id))
        main = pictures.first?.id
    }

    mutating func toggle(_ id: Picture.ID) {
        if kept.contains(id) {
            kept.remove(id)
            if main == id { main = pictures.first { kept.contains($0.id) }?.id }
        } else {
            kept.insert(id)
            if main == nil { main = id }
        }
    }

    mutating func makeMain(_ id: Picture.ID) {
        kept.insert(id)
        main = id
    }

    /// Main first, because the first stored picture is the one sent to the image model.
    var orderedJPEGs: [Data] {
        let keptPictures = pictures.filter { kept.contains($0.id) }
        let first = keptPictures.filter { $0.id == main }
        return (first + keptPictures.filter { $0.id != main }).map(\.jpeg)
    }
}

private struct DraftEditor: View {
    @Binding var draft: ObjectDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("^[\(draft.kept.count) picture](inflect: true) kept")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                              spacing: 10) {
                        ForEach(Array(draft.pictures.enumerated()), id: \.element.id) { index, picture in
                            tile(picture, number: index + 1)
                        }
                    }
                    Text("Tap a picture to keep or drop it. Tap a star to make that the main picture — the one used when designing a room.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").font(.headline)
                    TextField("Green velvet sofa", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                    if let source = draft.source, !source.isEmpty {
                        Text("From \(source)").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Kind").font(.headline)
                        Spacer()
                        KindPicker(kind: $draft.kind)
                    }
                    Text(KindPicker.explanation).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private func tile(_ picture: ObjectDraft.Picture, number: Int) -> some View {
        let isKept = draft.kept.contains(picture.id)
        let isMain = draft.main == picture.id

        return Button { draft.toggle(picture.id) } label: {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay { Image(uiImage: picture.preview).resizable().scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(isKept ? 1 : 0.35)
                .overlay {
                    if isMain {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isKept ? Color.accentColor : .white)
                        .background(Circle().fill(isKept ? .white : .black.opacity(0.25)))
                        .padding(6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Picture \(number)")
        .accessibilityValue(isKept ? (isMain ? "Kept, main picture" : "Kept") : "Dropped")
        .overlay(alignment: .topLeading) {
            Button { draft.makeMain(picture.id) } label: {
                Image(systemName: isMain ? "star.fill" : "star")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isMain ? .yellow : .white)
                    .padding(7)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .padding(4)
            .accessibilityLabel(isMain ? "Main picture \(number)" : "Make picture \(number) the main one")
        }
    }
}
