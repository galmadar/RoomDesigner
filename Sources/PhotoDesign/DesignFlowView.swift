import SwiftData
import SwiftUI
import simd

/// Where you stand, what goes in, and how it should feel — one question a screen.
struct DesignFlowView: View {
    let room: ScannedRoom

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LibraryObject.createdAt, order: .reverse) private var library: [LibraryObject]
    @ObservedObject private var accents = RoomAccents.shared
    @StateObject private var draft: DesignDraft
    @StateObject private var run = PhotoDesignRun()
    @StateObject private var thumbnails = ProductThumbnails()

    @State private var step = 0
    @State private var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?

    init(room: ScannedRoom) {
        self.room = room
        _draft = StateObject(wrappedValue: DesignDraft(room: room))
    }

    private var accent: Color { accents.accent(for: room) }
    private var photos: [ScanPhoto] { room.sortedPhotos }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                steps
            }
        }
        .tint(accent)
        .environment(\.roomAccent, accent)
        .task { await prepare() }
        .task(id: library.map(\.id)) { await thumbnails.load(library) }
    }

    private var topBar: some View {
        HStack {
            Button(step == 0 ? "Cancel" : "Back") {
                if step == 0 { dismiss() } else { withAnimation(.easeOut(duration: 0.18)) { step -= 1 } }
            }
            .font(.system(size: 16))
            .foregroundStyle(Paper.secondaryInk)
            .frame(minWidth: 48, minHeight: 44, alignment: .leading)
            .disabled(run.isWorking)

            Spacer()
            StepDots(step: step)
            Spacer()

            Color.clear.frame(width: 48, height: 44)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    @ViewBuilder private var steps: some View {
        let placed = PhotoDesignScene.placedProducts(room.proposals, library: library)
        switch step {
        case 0:
            WhereStep(room: room, draft: draft, bounds: bounds, onNext: { advance() })
        case 1:
            WhatStep(draft: draft, placed: placed, library: library,
                     thumbnails: thumbnails, onNext: { advance() })
        default:
            HowStep(room: room, draft: draft, chosen: chosen(from: placed),
                    unplaced: unplacedObjects, sourcePhoto: sourcePhoto,
                    run: run, onMake: { make() })
        }
    }

    private func advance() {
        withAnimation(.easeOut(duration: 0.18)) { step += 1 }
    }

    // MARK: - What the three answers add up to

    /// Markers are handed out over everything on the plan, so a piece keeps its
    /// colour even when the one before it is left out of this picture.
    private func chosen(from placed: [PlacedProduct]) -> [PlacedProduct] {
        placed.filter { $0.marker != nil && !draft.excluded.contains($0.proposal.id) }
    }

    private var unplacedObjects: [LibraryObject] {
        draft.unplacedIDs.compactMap { id in library.first { $0.id == id } }
    }

    private var freeCamera: Camera? {
        bounds.map {
            Camera.standing(at: draft.freePosition, in: $0, eyeHeight: 1.5,
                            yaw: draft.freeYaw, pitch: -8 * .pi / 180)
        }
    }

    private var shot: Shot? {
        switch draft.angle {
        case .photo(let index):
            guard photos.indices.contains(index), let viewpoint = photos[index].viewpoint else { return nil }
            return PhotoDesignScene.shot(for: viewpoint)
        case .free:
            return freeCamera.map { PhotoDesignScene.freeShot($0) }
        }
    }

    /// The photo sent with the request: the chosen spot's, or one taken near the free camera.
    private var sourcePhoto: ScanPhoto? {
        switch draft.angle {
        case .photo(let index): return photos.indices.contains(index) ? photos[index] : nil
        case .free: return freeCamera.flatMap { PhotoDesignScene.nearestPhoto(to: $0, among: photos) }
        }
    }

    private var angleLabel: String {
        if case .photo(let index) = draft.angle { return "Photo \(index + 1)" }
        return "Any angle"
    }

    private func prepare() async {
        await accents.load(room)
        guard bounds == nil, let captured = room.capturedRoom else { return }
        let mesh = RoomGeometry.build(from: captured)
        let measured = mesh.bounds
        bounds = measured
        if draft.freePosition == .zero {
            draft.stand(inCorner: measured)
        }
    }

    /// Hands the picture to ``PictureJobs`` and closes. Nothing is awaited here:
    /// the render and the request both belong to a job that outlives this screen.
    private func make() {
        guard let captured = room.capturedRoom, let shot else { return }
        let proposals = room.proposals
        let all = PhotoDesignScene.placedProducts(proposals, library: library)
        let picked = chosen(from: all)
        let unplaced = unplacedObjects

        let products = picked.compactMap { product in
            product.object.mainImageData.map {
                PhotoDesignRun.Order.Product(name: Self.name(of: product.object),
                                             libraryObjectID: product.object.id,
                                             imageData: $0, marker: product.marker)
            }
        } + unplaced.compactMap { object in
            object.mainImageData.map {
                PhotoDesignRun.Order.Product(name: Self.name(of: object), libraryObjectID: object.id,
                                             imageData: $0, marker: nil)
            }
        }

        PictureJobs.shared.start(
            .init(prompt: draft.trimmedPrompt, model: draft.model,
                  photoData: sourcePhoto?.imageData, photoThumbnail: sourcePhoto?.thumbnailData,
                  angle: angleLabel, capturedRoom: captured, proposals: proposals,
                  markerColours: PhotoDesignScene.markerColours(picked), shot: shot,
                  products: Array(products.prefix(PhotoDesignScene.maxProducts))),
            room: room, context: context)
        dismiss()
    }

    private static func name(of object: LibraryObject) -> String {
        let trimmed = object.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Product" : trimmed
    }
}

/// The three answers, while they are still being given.
@MainActor
final class DesignDraft: ObservableObject {
    enum Angle: Hashable { case photo(Int), free }

    @Published var angle: Angle
    @Published var freePosition: SIMD2<Float> = .zero
    @Published var freeYaw: Float = 0
    /// Pieces on the plan deliberately left out of this picture, by proposal.
    @Published var excluded: Set<UUID> = []
    @Published var unplacedIDs: [UUID] = []
    @Published var prompt = ""
    @Published var model: PhotoDesignModel = .nanoBanana

    init(room: ScannedRoom) {
        angle = room.sortedPhotos.isEmpty ? .free : .photo(0)
    }

    var trimmedPrompt: String {
        String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
    }

    /// Opening from a corner facing the middle shows the floor and the far
    /// corner; the middle of the room facing level shows a blank wall.
    func stand(inCorner bounds: (min: SIMD3<Float>, max: SIMD3<Float>)) {
        let centre = Camera.centre(of: bounds)
        let corner = SIMD2(bounds.min.x + (bounds.max.x - bounds.min.x) * 0.18,
                           bounds.min.z + (bounds.max.z - bounds.min.z) * 0.18)
        freePosition = Camera.clamp(corner, in: bounds)
        let toCentre = centre - freePosition
        freeYaw = atan2(toCentre.x, -toCentre.y)
    }
}
