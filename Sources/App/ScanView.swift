import SwiftUI
import simd

/// Seeing the scan: the room as it was captured, from wherever you stand in it.
///
/// A screen of its own, beside Design and Walk. It is how you check a scan came
/// out properly before designing anything from it, and — since the plan under
/// it became the whole instrument — where the furniture that goes into the
/// picture is arranged.
struct ScanView: View {
    let room: ScannedRoom

    @ObservedObject private var accents = RoomAccents.shared

    /// One renderer and one mesh for the screen's lifetime — rebuilding either
    /// per frame is what made dragging stutter.
    @StateObject private var previews = RoomPreview()

    @State private var position: SIMD2<Float> = .zero
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var eyeHeight: Float = 1.5
    @State private var fieldOfView: Float = 65 * .pi / 180
    @State private var kind: ConditioningImages.Kind = .room
    @State private var isDragging = false
    @State private var snap: PhotoSnap?
    @State private var photoPreview: UIImage?
    /// The floor's own outline, which is what "inside the room" means here.
    @State private var floor: RoomFloor?

    private static let wallMargin: Float = 0.3

    private var accent: Color { accents.accent(for: room) }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            if let captured = room.capturedRoom {
                content(FloorPlan(room: captured))
            } else {
                unscanned
            }
        }
        .navigationTitle("Seeing the scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .tint(accent)
        .environment(\.roomAccent, accent)
        .task { await accents.load(room) }
        .task { prepare() }
        .task(id: photoPreviewKey) { await renderPhotoPreview() }
        .onChange(of: position) { render() }
        .onChange(of: yaw) { render() }
        .onChange(of: pitch) { render() }
        .onChange(of: eyeHeight) { render() }
        .onChange(of: fieldOfView) { render() }
        .onChange(of: kind) { render() }
        .onChange(of: room.proposalsData) { rebuild() }
        .onChange(of: isDragging) { if !isDragging { render() } }   // sharpen on release
    }

    private func content(_ plan: FloorPlan) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                viewfinder
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ways
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                explanation
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                PlanBoard(room: room, plan: plan,
                          position: $position, yaw: $yaw, fieldOfView: $fieldOfView,
                          isDragging: $isDragging, eyeHeight: $eyeHeight,
                          lens: .square,
                          photoSpots: room.sortedPhotos.map(\.planSpot),
                          activeSpot: activePhoto,
                          onPickSpot: { snapToPhoto($0) })
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                dolly
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
            }
        }
    }

    private var unscanned: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("Nothing scanned")
                .question()
                .multilineTextAlignment(.center)
            Text("This room has no scan, so there is nothing to look at.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    // MARK: - The render

    private var viewfinder: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewfinderView(image: activePhoto == nil ? previews.image : (photoPreview ?? previews.image),
                           yaw: $yaw, pitch: $pitch, isDragging: $isDragging)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)

            if let index = activePhoto {
                Text("Standing where photo \(index + 1) was taken, seeing exactly what it saw. Move or turn to look around freely.")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The four ways of looking at the same viewpoint.
    private var ways: some View {
        HStack(spacing: 3) {
            ForEach(ConditioningImages.Kind.allCases) { option in
                let on = kind == option
                Button { kind = option } label: {
                    Text(option.label)
                        .font(.system(size: 15, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Paper.ink : Paper.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Paper.card)
                                    .shadow(color: Paper.cardShadow, radius: 1.5, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Paper.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var explanation: some View {
        if !kind.isConditioning {
            Text("The room as scanned — grey is what RoomPlan found, green is what you added.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Walking the camera in and out

    /// The lens and the eye height are the plan's, so they are the same control
    /// here as on the design flow's mini screen. These two are not: they step
    /// the camera along the way it is facing, which only makes sense beside a
    /// picture you are looking at.
    private var dolly: some View {
        HStack(spacing: 10) {
            Button { step(-0.35) } label: {
                Label("Back", systemImage: "minus.magnifyingglass")
            }
            .buttonStyle(QuietButtonStyle())

            Button { step(0.35) } label: {
                Label("Closer", systemImage: "plus.magnifyingglass")
            }
            .buttonStyle(QuietButtonStyle())
        }
    }

    /// Steps along the way the camera is facing, so Back and Closer mean what
    /// you are looking at, not a compass direction.
    ///
    /// Stopped at the wall rather than at the bounding box, which a room scanned
    /// at an angle overhangs — walking out through one is the other way to end
    /// up looking at the back of the room, and a black frame.
    private func step(_ metres: Float) {
        let heading = SIMD2(sin(yaw), -cos(yaw))
        let stepped = position + heading * metres
        if let floor {
            position = floor.keepInside(stepped, margin: Self.wallMargin)
        } else if let bounds = previews.bounds {
            position = Camera.clamp(stepped, in: bounds)
        }
    }

    // MARK: - Photo spots

    /// The free camera's values at the moment it jumped to a photo. While they still
    /// match, the preview is that photo's exact camera; any nudge makes it free again.
    private struct PhotoSnap: Equatable {
        var index: Int
        var position: SIMD2<Float>
        var yaw: Float
        var pitch: Float
        var eyeHeight: Float
        var fieldOfView: Float
    }

    private var activePhoto: Int? {
        guard let snap else { return nil }
        let now = PhotoSnap(index: snap.index, position: position, yaw: yaw, pitch: pitch,
                            eyeHeight: eyeHeight, fieldOfView: fieldOfView)
        return now == snap ? snap.index : nil
    }

    /// The free controls get the nearest values they can hold; the preview uses the photo's own camera.
    private func snapToPhoto(_ index: Int) {
        let photos = room.sortedPhotos
        guard photos.indices.contains(index), let spot = photos[index].planSpot,
              let bounds = previews.bounds else { return }
        position = Camera.clamp(spot.position, in: bounds)
        yaw = spot.yaw
        pitch = min(max(spot.pitch, -40 * .pi / 180), 40 * .pi / 180)
        eyeHeight = min(max(spot.height - bounds.min.y, 0.4), 2.2)
        fieldOfView = Lens.square.clamped(spot.fieldOfView)
        snap = PhotoSnap(index: index, position: position, yaw: yaw, pitch: pitch,
                         eyeHeight: eyeHeight, fieldOfView: fieldOfView)
    }

    private struct PhotoPreviewKey: Equatable {
        var photo: Int?
        var kind: ConditioningImages.Kind
        var proposals: Data?
    }

    private var photoPreviewKey: PhotoPreviewKey {
        PhotoPreviewKey(photo: activePhoto, kind: kind, proposals: room.proposalsData)
    }

    private func renderPhotoPreview() async {
        let photos = room.sortedPhotos
        guard let index = activePhoto, photos.indices.contains(index),
              let viewpoint = photos[index].viewpoint, let captured = room.capturedRoom
        else { return photoPreview = nil }
        let mesh = RoomGeometry.build(from: captured, proposals: room.proposals)
        let image = await ShotRenderer.shared.image(of: mesh, shot: PhotoDesignScene.shot(for: viewpoint),
                                                    size: RoomPreview.finalSize, kind: kind)
        if !Task.isCancelled { photoPreview = image }
    }

    // MARK: - Rendering

    private func prepare() {
        guard previews.bounds == nil, let captured = room.capturedRoom else { return }
        let built = RoomGeometry.build(from: captured, proposals: room.proposals)
        previews.load(built)

        // Open on a shot worth looking at. Standing in the middle facing dead
        // level puts a blank wall in the frame; from a corner, angled slightly
        // down, you see the floor, the far corner and whatever is in between.
        let bounds = built.bounds
        let centre = Camera.centre(of: bounds)
        let corner = SIMD2(bounds.min.x + (bounds.max.x - bounds.min.x) * 0.18,
                           bounds.min.z + (bounds.max.z - bounds.min.z) * 0.18)
        let inside = RoomFloor(room: captured)
        floor = inside
        // 18% into the box is outside the walls of a room scanned at an angle,
        // which would open this screen on a black frame.
        position = inside?.keepInside(corner, margin: Self.wallMargin)
            ?? Camera.clamp(corner, in: bounds)
        let toCentre = centre - position
        yaw = atan2(toCentre.x, -toCentre.y)
        pitch = -8 * .pi / 180
        render()
    }

    private func rebuild() {
        guard let captured = room.capturedRoom else { return }
        previews.load(RoomGeometry.build(from: captured, proposals: room.proposals))
        render()
    }

    private func render() {
        previews.request(position: position, yaw: yaw, pitch: pitch,
                         eyeHeight: eyeHeight, fieldOfView: fieldOfView,
                         kind: kind, draft: isDragging)
    }
}
