import SwiftData
import SwiftUI

/// "Design with photos": pick an angle, say what to change, pick a model, and get
/// back a photo of the real room with the chosen products in it.
struct PhotoDesignView: View {
    let room: ScannedRoom
    /// The free camera as the room screen had it, so "Free angle" is what the plan shows.
    let freeCamera: Camera

    enum Angle: Hashable { case photo(Int), free }

    @Environment(\.modelContext) private var context
    @Query(sort: \LibraryObject.createdAt, order: .reverse) private var library: [LibraryObject]
    @StateObject private var run = PhotoDesignRun()
    @StateObject private var thumbnails = ProductThumbnails()

    @State private var angle: Angle
    @State private var prompt = ""
    @State private var model: PhotoDesignModel = .nanoBanana
    @State private var runningModel: PhotoDesignModel = .nanoBanana
    @State private var unplacedIDs: [UUID] = []
    @State private var isAddingUnplaced = false
    @State private var render: UIImage?
    @State private var photoPreview: UIImage?
    @State private var isCameraOutside = false
    @State private var resultImage: UIImage?
    @State private var isShowingResult = false
    @FocusState private var isEditingPrompt: Bool

    /// Photo spots come first: the one the room screen stood at, else the first taken.
    init(room: ScannedRoom, freeCamera: Camera, startingPhoto: Int?) {
        self.room = room
        self.freeCamera = freeCamera
        let count = room.sortedPhotos.count
        if let startingPhoto, startingPhoto < count {
            _angle = State(initialValue: .photo(startingPhoto))
        } else {
            _angle = State(initialValue: count > 0 ? .photo(0) : .free)
        }
    }

    var body: some View {
        let placed = PhotoDesignScene.placedProducts(room.proposals, library: library)
        let included = placed.filter { $0.marker != nil }
        let leftOut = placed.filter { $0.marker == nil }
        let unplaced = unplacedIDs.compactMap { id in library.first { $0.id == id } }

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                angleSection
                previewSection
                productsSection(included: included, leftOut: leftOut, unplaced: unplaced)
                promptSection
                modelSection
                generateSection(included: included, unplaced: unplaced)
                resultSection
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Design with photos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAddingUnplaced) {
            LibraryPicker(
                title: "Add without placing",
                footnote: "For things with no spot on the floor plan, like a painting, a mirror or curtains. The picture puts them wherever your prompt says, so say where: \"hang the painting above the sofa\".",
                unavailable: { object in
                    if unplacedIDs.contains(object.id) { return "Already in the picture" }
                    if placed.contains(where: { $0.object.id == object.id }) { return "Already placed on the floor plan" }
                    return nil
                },
                onPick: { unplacedIDs = unplacedIDs + [$0.id] })
        }
        .alert("Couldn't make the picture",
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { run.reset() } })) {
            Button("OK") { run.reset() }
        } message: { Text(failure ?? "") }
        .task(id: RenderKey(angle: angle, proposals: room.proposalsData, library: library.map(\.id))) {
            await loadPreview()
        }
        .task(id: library.map(\.id)) { await thumbnails.load(library) }
        .task(id: run.result?.persistentModelID) { await loadResult() }
    }

    // MARK: - Angle

    private var photos: [ScanPhoto] { room.sortedPhotos }

    /// The photo sent with the request: the chosen spot's, or one taken near the free camera.
    private var sourcePhoto: ScanPhoto? {
        switch angle {
        case .photo(let index): return photos.indices.contains(index) ? photos[index] : nil
        case .free: return PhotoDesignScene.nearestPhoto(to: freeCamera, among: photos)
        }
    }

    private var shot: Shot? {
        switch angle {
        case .photo(let index):
            guard photos.indices.contains(index), let viewpoint = photos[index].viewpoint else { return nil }
            return PhotoDesignScene.shot(for: viewpoint)
        case .free:
            return PhotoDesignScene.freeShot(freeCamera)
        }
    }

    private var angleLabel: String {
        if case .photo(let index) = angle { return "Photo \(index + 1)" }
        return "Free angle"
    }

    private var angleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Angle").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos.indices, id: \.self) { index in
                        angleCard("Photo \(index + 1)", selected: angle == .photo(index),
                                  action: { angle = .photo(index) }) {
                            if let image = photos[index].thumbnail {
                                Image(uiImage: image).resizable().scaledToFill()
                            }
                        }
                    }
                    angleCard("Free angle", selected: angle == .free, action: { angle = .free }) {
                        Image(systemName: "move.3d").font(.title2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 1)
            }
            Text(angleExplanation).font(.caption2).foregroundStyle(.secondary)
            if isCameraOutside {
                Label("The camera is standing outside the room's walls, so the scan shows only the back of a wall. Move it inside on the floor plan first.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var angleExplanation: String {
        switch angle {
        case .photo:
            return "The picture will match this photo: the same spot and the same view."
        case .free:
            if let photo = sourcePhoto, let index = photos.firstIndex(where: { $0 === photo }) {
                return "The view you set on the floor plan. Photo \(index + 1) was taken close by, so it goes too, to show the room's real colours and light."
            }
            if photos.isEmpty {
                return "The view you set on the floor plan. This room has no photos, so its colours and materials come from your prompt."
            }
            return "The view you set on the floor plan. No photo was taken close enough to it (within a metre and 30°), so the room's colours and materials come from your prompt."
        }
    }

    private func angleCard<Content: View>(_ label: String, selected: Bool, action: @escaping () -> Void,
                                          @ViewBuilder content: () -> Content) -> some View {
        let inner = content()
        return Button(action: action) {
            VStack(spacing: 4) {
                Color(.secondarySystemBackground)
                    .frame(width: 76, height: 76)
                    .overlay { inner }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                    }
                Text(label).font(.caption)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Preview

    private struct RenderKey: Equatable {
        var angle: Angle
        var proposals: Data?
        var library: [UUID]
    }

    private var previewSection: some View {
        let hasPhoto = sourcePhoto != nil
        let aspect = shot.map { $0.crop.width / $0.crop.height } ?? 4 / 3
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if hasPhoto { tile(photoPreview, aspect: aspect, label: "Your photo") }
                tile(render, aspect: aspect, label: "The scan with product boxes")
            }
            Text(hasPhoto
                 ? "Your photo, and the scan from the same spot with a coloured box where each product goes. The boxes won't be in the picture."
                 : "The scan from this angle, with a coloured box where each product goes. The boxes won't be in the picture.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func tile(_ image: UIImage?, aspect: CGFloat, label: String) -> some View {
        Color(.secondarySystemBackground)
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(label)
    }

    /// What is on screen is what gets sent: the same render is uploaded.
    private func loadPreview() async {
        render = nil
        if let data = sourcePhoto?.imageData {
            photoPreview = await Task.detached(priority: .userInitiated) {
                LibraryImage.thumbnail(from: data, maxPixelSize: 900)
            }.value
        } else {
            photoPreview = nil
        }
        guard let captured = room.capturedRoom, let shot else { return }
        let eye = SIMD2(freeCamera.eye.x, freeCamera.eye.z)
        isCameraOutside = angle == .free && PhotoDesignScene.isOnFloor(eye, of: captured) == false
        let proposals = room.proposals
        let placed = PhotoDesignScene.placedProducts(proposals, library: library)
        let mesh = PhotoDesignScene.mesh(of: captured, proposals: proposals, placed: placed, camera: shot.camera)
        let image = await ShotRenderer.shared.image(of: mesh, shot: shot, size: PhotoDesignScene.renderSize)
        if !Task.isCancelled { render = image }
    }

    // MARK: - Products

    private func productsSection(included: [PlacedProduct], leftOut: [PlacedProduct],
                                 unplaced: [LibraryObject]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Products").font(.headline)

            ForEach(included) { product in
                productRow(name: product.object.name, id: product.object.id, marker: product.marker,
                           note: "The \(product.marker?.rawValue ?? "") box on the floor plan")
            }
            ForEach(unplaced) { object in
                productRow(name: object.name, id: object.id, marker: nil,
                           note: "Not placed. It goes wherever your prompt says.",
                           onRemove: { unplacedIDs = unplacedIDs.filter { $0 != object.id } })
            }

            if !leftOut.isEmpty {
                Text("One picture takes at most \(PhotoDesignScene.maxProducts) products, so these are left out: \(leftOut.map(\.object.name).joined(separator: ", ")).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if included.isEmpty && unplaced.isEmpty {
                Text("To put a product in a particular spot, place it on the floor plan: Furniture, then Library. Or add one here without placing it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Button { isAddingUnplaced = true } label: {
                Label("Add without placing", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .disabled(included.count + unplaced.count >= PhotoDesignScene.maxProducts)
        }
    }

    private func productRow(name: String, id: UUID, marker: Marker?, note: String,
                            onRemove: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            MarkerSwatch(marker: marker)
            ProductThumbnail(image: thumbnails.images[id], size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).lineLimit(1)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(name)")
            }
        }
    }

    // MARK: - Prompt and model

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What to change").font(.headline)
            TextField("Hang the painting above the sofa, warm evening light",
                      text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
                .focused($isEditingPrompt)
            SuggestionIdeas(text: $prompt, room: room)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model").font(.headline)
            Picker("Model", selection: $model) {
                ForEach(PhotoDesignModel.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(model.summary).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Generate

    private var trimmedPrompt: String {
        String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
    }

    private var failure: String? {
        if case .failed(let message) = run.stage { return message }
        return nil
    }

    private func generateSection(included: [PlacedProduct], unplaced: [LibraryObject]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                generate(included: included, unplaced: unplaced)
            } label: {
                Label(run.isWorking ? "Working…" : "Generate", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(trimmedPrompt.isEmpty || render == nil || shot == nil || run.isWorking)

            if trimmedPrompt.isEmpty && !run.isWorking {
                Text("Say what you'd like first, even just \"put these in the room\".")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            progress
        }
    }

    @ViewBuilder private var progress: some View {
        switch run.stage {
        case .uploading(let done, let total):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Sending the pictures… \(done) of \(total)").font(.caption)
            }
        case .designing(let since):
            HStack(alignment: .top, spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Making the picture with \(runningModel.name)…")
                        Text(since, style: .timer).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    Text(runningModel.waitingNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        case .downloading:
            HStack(spacing: 10) { ProgressView(); Text("Fetching the picture…").font(.subheadline) }
        case .idle, .finished, .failed:
            EmptyView()
        }
    }

    @ViewBuilder private var resultSection: some View {
        if case .finished = run.stage, let picture = run.result {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your picture").font(.headline)
                Button { isShowingResult = true } label: {
                    if let image = resultImage ?? picture.thumbnail {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your picture")
                Label("Saved to this room's pictures. Tap it to see it full size or share it.",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .fullScreenCover(isPresented: $isShowingResult) {
                PictureDetailView(picture: picture, onDelete: nil)
            }
        }
    }

    private func loadResult() async {
        guard let data = run.result?.imageData else { return resultImage = nil }
        resultImage = await Task.detached(priority: .userInitiated) {
            LibraryImage.thumbnail(from: data, maxPixelSize: 1600)
        }.value
    }

    private func generate(included: [PlacedProduct], unplaced: [LibraryObject]) {
        guard let render, let png = render.pngData(), let shot else { return }
        isEditingPrompt = false      // the keyboard would hide the progress
        let photo = sourcePhoto
        let products = included.compactMap { product in
            product.object.mainImageData.map {
                PhotoDesignRun.Order.Product(name: Self.name(of: product.object), libraryObjectID: product.object.id,
                                             imageData: $0, marker: product.marker)
            }
        } + unplaced.compactMap { object in
            object.mainImageData.map {
                PhotoDesignRun.Order.Product(name: Self.name(of: object), libraryObjectID: object.id,
                                             imageData: $0, marker: nil)
            }
        }
        runningModel = model
        run.start(.init(prompt: trimmedPrompt, model: model,
                        photoData: photo?.imageData, photoThumbnail: photo?.thumbnailData,
                        angle: angleLabel, renderPNG: png, aspectRatio: shot.aspectRatio,
                        products: Array(products.prefix(PhotoDesignScene.maxProducts))),
                  room: room, context: context)
    }

    private static func name(of object: LibraryObject) -> String {
        let trimmed = object.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Product" : trimmed
    }
}
