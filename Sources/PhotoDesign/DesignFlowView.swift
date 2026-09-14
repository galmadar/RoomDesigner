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

    @State private var step: Int
    @State private var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
    @State private var preview: UIImage?

    /// Set when the walk's shutter opened this, from where you were standing.
    private let standing: Standing?

    init(room: ScannedRoom, standing: Standing? = nil) {
        self.room = room
        self.standing = standing
        _draft = StateObject(wrappedValue: DesignDraft(room: room, standing: standing))
        // Standing there has already answered "where", so the flow opens on the
        // next question rather than asking one that is behind you.
        _step = State(initialValue: standing == nil ? 0 : 1)
    }

    private var accent: Color { accents.accent(for: room) }
    private var photos: [ScanPhoto] { room.sortedPhotos }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if standing != nil { shotCard }
                steps
            }
        }
        .tint(accent)
        .environment(\.roomAccent, accent)
        .task { await prepare() }
        .task { await drawPreview() }
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

    // MARK: - The shot the shutter took

    /// The room drawn through the very camera the picture will be made with,
    /// cropped to the frame it will be cut to — so what was on screen when the
    /// shutter was pressed is still on screen while the questions are answered.
    private var shotCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Paper.tint
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                } else {
                    ProgressView().tint(Paper.mutedInk)
                }
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxHeight: 210)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Paper.outline, lineWidth: 1)
            }

            Text("From where you were standing.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The room from where you were standing")
    }

    /// One still, drawn from the shot that will be uploaded — not a second
    /// renderer, and not a second camera that could disagree with it.
    private func drawPreview() async {
        guard standing != nil, preview == nil,
              let captured = room.capturedRoom, let shot else { return }
        let proposals = room.proposals
        let mesh = await Task.detached(priority: .userInitiated) {
            RoomGeometry.build(from: captured, proposals: proposals)
        }.value
        preview = await ShotRenderer.shared.image(of: mesh, shot: shot, size: 768)
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

    /// From the walk the camera is taken as it was handed over: that spot was
    /// already held inside the floor polygon, and clamping it to the bounding
    /// box — which a room scanned at an angle overhangs — could push a camera
    /// that was standing in the room back out of it. Every other way in here is
    /// unchanged, literals and all.
    private var freeCamera: Camera? {
        if draft.cameFromTheWalk { return draft.standingCamera }
        return bounds.map {
            Camera.standing(at: draft.freePosition, in: $0, eyeHeight: draft.freeEyeHeight,
                            yaw: draft.freeYaw, pitch: draft.freePitch,
                            fieldOfView: draft.freeFieldOfView)
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
    ///
    /// Only ever a photo that knows where it was taken from. An uploaded photo
    /// left unplaced shows some other part of the room from some other spot, and
    /// sending it as `room_photo_url` would tell the model it is looking at the
    /// very view it is being asked to draw — a wrong picture with nothing on
    /// screen to say why. `nearestPhoto` already skips them; this is the other
    /// way in, and it is closed here so nothing downstream has to know.
    private var sourcePhoto: ScanPhoto? {
        switch draft.angle {
        case .photo(let index):
            guard photos.indices.contains(index), photos[index].isPlaced else { return nil }
            return photos[index]
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
        // Never over a spot the walk handed in, which may legitimately sit near
        // the world origin.
        if !draft.cameFromTheWalk, draft.freePosition == .zero {
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
    /// The free camera used to tip a fixed 8°, at a fixed height, through a
    /// fixed lens. They are fields now because the walk hands its own in.
    @Published var freePitch: Float = -8 * .pi / 180
    @Published var freeEyeHeight: Float = 1.5
    /// World y of the floor. Only meaningful beside a handed-in position: the
    /// plan's own camera measures its height from the bounding box instead.
    @Published var freeLevel: Float = 0
    @Published var freeFieldOfView: Float = 65 * .pi / 180
    /// Pieces on the plan deliberately left out of this picture, by proposal.
    @Published var excluded: Set<UUID> = []
    @Published var unplacedIDs: [UUID] = []
    @Published var prompt = ""
    @Published var model: PhotoDesignModel = .nanoBanana

    /// Whether the camera was handed in by the walk, where it was already held
    /// inside the floor polygon and so must not be clamped to a box again.
    let cameFromTheWalk: Bool

    init(room: ScannedRoom, standing: Standing? = nil) {
        cameFromTheWalk = standing != nil
        guard let standing else {
            // The first photo that has a place in the room, never simply the
            // first: an unplaced one has no camera to frame a picture through,
            // so opening on it would offer an angle that cannot be used.
            angle = room.sortedPhotos.firstIndex(where: \.isPlaced).map { .photo($0) } ?? .free
            return
        }
        angle = .free
        freePosition = standing.position
        freeYaw = standing.yaw
        freePitch = standing.pitch
        freeEyeHeight = standing.eyeHeight
        freeLevel = standing.level
        freeFieldOfView = standing.fieldOfView
    }

    /// The handed-in camera, rebuilt from the fields the draft now carries.
    var standingCamera: Camera {
        Standing(position: freePosition, yaw: freeYaw, pitch: freePitch,
                 eyeHeight: freeEyeHeight, level: freeLevel,
                 fieldOfView: freeFieldOfView).camera
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
