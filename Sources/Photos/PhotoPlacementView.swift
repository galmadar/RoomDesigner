import SwiftData
import SwiftUI
import simd

/// Standing a photograph in the room by hand.
///
/// Every piece of this already existed and is borrowed rather than rebuilt: the
/// plan is the same instrument as everywhere else, so moving and turning are
/// what you already know; the render comes from ``InsideRenderer`` through the
/// photo's own camera and crop, so it covers exactly what the photograph
/// covers; and the two are crossed with a slider, which is the walk's compare —
/// the one way anyone can actually judge a match. If the walls cross cleanly
/// the pose is right. If they slide past each other it is not, and you move.
struct PhotoPlacementView: View {
    let room: ScannedRoom
    let photo: ScanPhoto
    let onFinished: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.roomAccent) private var accent

    @StateObject private var inside = InsideRenderer()

    @State private var placing = PhotoPose.Placing()
    @State private var blend: Double = 0.5
    @State private var isDragging = false
    @State private var image: UIImage?
    @State private var hasStood = false

    private var imageSize: SIMD2<Float>? { image.map(PhotoPose.imageSize(of:)) }

    /// What would be written if Place were tapped now — and, the same thing,
    /// what the render on screen is drawn through.
    private var viewpoint: PhotoViewpoint? {
        imageSize.flatMap { PhotoPose.viewpoint(placing, imageSize: $0) }
    }

    private var plan: FloorPlan? { room.capturedRoom.map { FloorPlan(room: $0) } }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    match
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    crossfade
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    if let plan {
                        PlanBoard(room: room, plan: plan,
                                  position: $placing.position, yaw: $placing.yaw,
                                  fieldOfView: $placing.horizontalFieldOfView,
                                  isDragging: $isDragging,
                                  eyeHeight: $placing.eyeHeight,
                                  lens: .shot, planHeight: 240,
                                  photoSpots: otherSpots,
                                  onPickSpot: { stand(like: $0) })
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                    }
                }
                // Clear of the button floating over the bottom, so the plan can
                // be scrolled out from under it rather than half-hidden by it.
                .padding(.bottom, 104)
            }

            VStack {
                Spacer(minLength: 0)
                Button("Place it here", action: place)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewpoint == nil)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .background {
                        LinearGradient(colors: [Paper.sheet.opacity(0), Paper.sheet],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                            .allowsHitTesting(false)
                    }
            }
        }
        .navigationTitle("Line it up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .task { await prepare() }
        .onChange(of: placing) { redraw(rough: isDragging) }
        .onChange(of: isDragging) { if !isDragging { redraw() } }
    }

    // MARK: - The two pictures

    private var match: some View {
        PhotoMatchView(render: inside.image, photograph: image,
                       aspect: viewpoint.map { CGFloat($0.aspect) } ?? 4.0 / 3.0,
                       blend: blend, yaw: $placing.yaw, pitch: $placing.pitch,
                       isDragging: $isDragging)
    }

    private var crossfade: some View {
        HStack(spacing: 10) {
            Text("Scan").font(.system(size: 13)).foregroundStyle(Paper.secondaryInk)
            Slider(value: $blend, in: 0...1)
                .frame(minHeight: 44)
                .accessibilityLabel("Blend between the scan and the photograph")
            Text("Photo").font(.system(size: 13)).foregroundStyle(Paper.secondaryInk)
        }
    }

    private var hint: String {
        guard inside.isLoaded else {
            return "This scan has no geometry to draw, so there is nothing to line the photograph up against. You can still say where you were standing on the plan."
        }
        return "Slide between the two. Drag the picture to turn and tilt, and move yourself on the plan below. When the walls cross cleanly, the photo is standing where it was taken."
    }

    // MARK: - Where the other photos were taken

    /// The room's other photo spots, so this one can be put beside them — with
    /// this photo's own left out, since it is the camera being moved.
    private var otherSpots: [PlanSpot?] {
        room.sortedPhotos.map { $0 === photo ? nil : $0.planSpot }
    }

    /// Starting from another photo's spot, which is often the honest answer:
    /// "about where that one was, a step to the left".
    private func stand(like index: Int) {
        let photos = room.sortedPhotos
        guard photos.indices.contains(index), let spot = photos[index].planSpot else { return }
        var moved = placing
        moved.position = spot.position
        moved.yaw = spot.yaw
        moved.pitch = min(max(spot.pitch, -PhotoPose.steepestPitch), PhotoPose.steepestPitch)
        moved.eyeHeight = spot.height - placing.level
        moved.horizontalFieldOfView = Lens.shot.clamped(spot.fieldOfView)
        placing = moved
    }

    // MARK: - Opening, drawing, keeping

    private func prepare() async {
        let data = photo.imageData
        image = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value

        guard !inside.isLoaded, let captured = room.capturedRoom else { return redraw() }
        let proposals = room.proposals
        let built = await Task.detached(priority: .userInitiated) { () -> (Mesh, RoomFloor?) in
            (RoomGeometry.build(from: captured, proposals: proposals), RoomFloor(room: captured))
        }.value
        inside.load(built.0)
        standAtOpening(built.1, bounds: built.0.bounds)
        redraw()
    }

    /// Where the photo already is if it has been placed before, and otherwise
    /// deep in the room facing its longest sightline — the spot the walk opens
    /// at, because it is the one that shows the most wall to line up against.
    private func standAtOpening(_ floor: RoomFloor?,
                                bounds: (min: SIMD3<Float>, max: SIMD3<Float>)) {
        guard !hasStood else { return }
        hasStood = true
        let level = floor?.level ?? bounds.min.y

        if let taken = photo.viewpoint {
            placing = PhotoPose.placing(of: taken, level: level)
            return
        }
        var opening = PhotoPose.Placing()
        opening.level = level
        opening.pitch = -8 * .pi / 180
        if let floor {
            opening.position = floor.deepestPoint
            opening.yaw = floor.heading(from: opening.position)
        } else {
            opening.position = Camera.centre(of: bounds)
        }
        placing = opening
    }

    /// Rough while a finger is down, sharp once it lifts — the same bargain the
    /// design flow's mini screen makes, through the same renderer.
    private func redraw(rough: Bool = false) {
        guard let viewpoint else { return }
        inside.request(PhotoDesignScene.shot(for: viewpoint), draft: rough)
    }

    private func place() {
        guard let viewpoint else { return }
        photo.place(viewpoint, by: .byHand)
        try? context.save()
        onFinished()
    }
}

/// The render and the photograph in one frame, one over the other.
///
/// Both are drawn at the photograph's own aspect, so they cover the same field
/// of view and a difference on screen is a real difference — the walk's compare
/// does exactly this, and for the same reason. Dragging turns and tilts, as on
/// every viewfinder in the app.
private struct PhotoMatchView: View {
    let render: UIImage?
    let photograph: UIImage?
    let aspect: CGFloat
    let blend: Double

    @Binding var yaw: Float
    @Binding var pitch: Float
    @Binding var isDragging: Bool

    /// Roughly a quarter turn across the width, as `ViewfinderView` has it.
    private let turnPerPoint: Float = .pi / 2 / 340

    @State private var anchor: (yaw: Float, pitch: Float)?

    var body: some View {
        ZStack {
            Color.black
            if let render {
                Image(uiImage: render).resizable().scaledToFill()
            }
            if let photograph {
                Image(uiImage: photograph)
                    .resizable()
                    .scaledToFill()
                    .opacity(blend)
            }
            if render == nil && photograph == nil {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(max(aspect, 0.2), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = anchor ?? (yaw, pitch)
                    if anchor == nil { anchor = start }
                    isDragging = true
                    yaw = start.yaw + Float(value.translation.width) * turnPerPoint
                    pitch = min(max(start.pitch - Float(value.translation.height) * turnPerPoint,
                                    -PhotoPose.steepestPitch), PhotoPose.steepestPitch)
                }
                .onEnded { _ in
                    anchor = nil
                    isDragging = false
                }
        )
        .accessibilityLabel("The scan crossed with the photograph. Drag to turn and tilt.")
    }
}
