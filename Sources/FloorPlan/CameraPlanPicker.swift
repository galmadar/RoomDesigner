import SwiftUI
import simd

/// The floor plan as an instrument: stand somewhere and point, and pick up the
/// furniture standing on the floor.
///
/// One canvas, no modes. It used to have two — camera or furniture, chosen
/// before you touched anything — because on a phone-sized plan every camera
/// drag risked grabbing a sofa. What that cost was one more thing to learn, and
/// two screens that each knew half the instrument. The grab is decided by what
/// is under the finger instead: the camera's own two handles win inside their
/// small reach, a piece of furniture wins where it is drawn, and bare floor
/// moves the map. Which was grabbed is settled once per drag, so a fast finger
/// cannot slip from one to the other halfway.
///
/// Bare floor used to teleport the camera. It is the map now because a drag on
/// nothing in particular means "move the map" on every map anyone has used, and
/// because the camera has a dot of its own to be dragged by — which is what the
/// hint under the plan has always said to do.
struct CameraPlanPicker: View {
    let plan: FloorPlan

    @Binding var position: SIMD2<Float>
    @Binding var yaw: Float
    @Binding var isDragging: Bool
    @Binding var fieldOfView: Float

    @Binding var proposals: [Proposal]
    @Binding var selection: Proposal.ID?

    /// Called once when a piece is picked up, never per drag frame — otherwise
    /// dragging a sofa across the room would fill the undo stack with every
    /// pixel it passed through.
    var onBeginEdit: () -> Void = {}

    /// What a proposal stands in for, when it is a library product.
    struct ProductLink {
        var name: String
        var thumbnail: UIImage?
        /// Its box colour in "Design with photos"; nil once the eight colours are used up.
        var marker: Marker?
    }
    var links: [Proposal.ID: ProductLink] = [:]

    /// What the plan is drawn on, so it can sit on the app's paper rather than a system grey.
    var canvas: Color = Color(.secondarySystemBackground)

    /// Off where there is no viewpoint to set, so the plan is only the furniture.
    var showsCamera = true

    /// Where each photo was taken, in the room's photo order; nil where the pose can't be read.
    var photoSpots: [PlanSpot?] = []
    /// The photo the camera stands at, if it hasn't moved since.
    var activeSpot: Int?
    var onPickSpot: (Int) -> Void = { _ in }

    @State private var grabbed: Grab?
    // Opening values so a simulator run can be zoomed or panned without a
    // finger; 1 and zero in a release build, where `RoomSeed` answers nothing.
    @State private var zoom: CGFloat = RoomSeed.planZoom ?? 1
    @State private var zoomAnchor: CGFloat = RoomSeed.planZoom ?? 1
    /// Where the map has been slid to, and where it stood when this drag began.
    @State private var pan: CGSize = RoomSeed.planPan ?? .zero
    @State private var panStart: CGSize = .zero

    private enum Grab: Equatable { case body, direction, proposal(Proposal.ID), map }

    private var coneLength: Float { 2.2 }

    /// How close a finger has to land to take the camera off a piece of
    /// furniture drawn under it. Both are smaller than the handles look: the
    /// dot is 22 points across and the knob 18, and a piece of furniture can
    /// still be picked up anywhere else along its own footprint.
    private let bodyReach: CGFloat = 30
    private let handleReach: CGFloat = 44

    /// The zoom and the pan are the map's own, never taken from what is
    /// selected or from where the camera stands — so nothing that is dragged
    /// can move the ground it is being dragged across.
    private func projection(for size: CGSize, zoom: CGFloat? = nil) -> PlanProjection? {
        PlanProjection(plan: plan, size: size, zoom: zoom ?? self.zoom, pan: pan)
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let projection = projection(for: size) else { return }
                FloorPlanView.draw(plan, in: context, using: projection, labels: true)
                drawPhotoSpots(in: context, using: projection)
                drawProposals(in: context, using: projection)
                if showsCamera {
                    drawCamera(in: context, using: projection)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let projection = projection(for: geometry.size) else { return }
                        isDragging = true
                        update(with: value, projection: projection)
                    }
                    .onEnded { _ in
                        grabbed = nil
                        isDragging = false
                    }
            )
            .simultaneousGesture(
                // About the point between the fingers, so the room does not slide
                // away from under the pinch that is meant to be examining it.
                MagnifyGesture()
                    .onChanged { value in
                        let scaled = min(max(zoomAnchor * value.magnification, 1), 8)
                        guard let now = projection(for: geometry.size),
                              let next = projection(for: geometry.size, zoom: scaled) else { return }
                        let moved = now.pan(zoomingTo: scaled, about: value.startLocation)
                        zoom = scaled
                        pan = next.clamped(moved)
                    }
                    .onEnded { _ in zoomAnchor = zoom }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    zoom = 1; zoomAnchor = 1; pan = .zero
                }
            }
            .overlay(alignment: .topTrailing) {
                if zoom > 1.01 {
                    Text("\(zoom, format: .number.precision(.fractionLength(1)))×")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                        .padding(8)
                }
            }
            // Real buttons over the drawn spots, so they're tappable and VoiceOver can find them.
            // The active one steps aside: the camera dot sits on it and must stay draggable.
            .overlay {
                if showsCamera, let projection = projection(for: geometry.size) {
                    ForEach(photoSpots.indices, id: \.self) { index in
                        if let spot = photoSpots[index], index != activeSpot {
                            Button { onPickSpot(index) } label: {
                                Color.clear.frame(width: 36, height: 36).contentShape(Circle())
                            }
                            .accessibilityLabel("Photo spot \(index + 1)")
                            .position(projection.point(spot.position))
                        }
                    }
                }
            }
        }
        .background(canvas)
    }

    // MARK: - Interaction

    private func direction() -> SIMD2<Float> { SIMD2(sin(yaw), -cos(yaw)) }
    private func handlePosition() -> SIMD2<Float> { position + direction() * coneLength }

    private func update(with value: DragGesture.Value, projection: PlanProjection) {
        // Decide once per drag what was grabbed, so a fast finger cannot slip
        // from turning the camera to dragging a chair halfway through.
        if grabbed == nil {
            grabbed = grab(at: value.startLocation, projection: projection)
            panStart = pan
        }
        let location = value.location

        switch grabbed {
        case .direction:
            let centre = projection.point(position)
            let dx = location.x - centre.x, dy = location.y - centre.y
            guard hypot(dx, dy) > 4 else { return }
            yaw = atan2(Float(dx), Float(-dy))

        case .proposal(let id):
            guard let index = proposals.firstIndex(where: { $0.id == id }) else { return }
            var updated = proposals
            updated[index].position = projection.position(location)
            proposals = updated

        case .body:
            position = projection.position(location)

        case .map:
            // Against where the map stood when the finger landed, so the pan
            // cannot accumulate on itself the way the old focus did.
            pan = projection.clamped(CGSize(width: panStart.width + value.translation.width,
                                            height: panStart.height + value.translation.height))

        case nil:
            break
        }
    }

    private func grab(at location: CGPoint, projection: PlanProjection) -> Grab {
        if showsCamera {
            let body = projection.point(position)
            let toBody = hypot(location.x - body.x, location.y - body.y)
            let handle = projection.point(handlePosition())
            let toHandle = hypot(location.x - handle.x, location.y - handle.y)
            if toHandle < handleReach && toHandle <= toBody { return .direction }
            if toBody < bodyReach { return .body }
        }

        // Topmost first, so a piece dropped on another can be picked up again.
        for proposal in proposals.reversed() where contains(proposal, location, projection) {
            selection = proposal.id
            onBeginEdit()
            return .proposal(proposal.id)
        }

        selection = nil
        return .map
    }

    private func contains(_ proposal: Proposal, _ location: CGPoint,
                          _ projection: PlanProjection) -> Bool {
        let centre = projection.point(proposal.position)
        let dx = Float(location.x - centre.x), dy = Float(location.y - centre.y)
        // Into the piece's own frame, so a rotated sofa is hit where it looks.
        let c = cos(-proposal.rotation), s = sin(-proposal.rotation)
        let localX = dx * c - dy * s, localY = dx * s + dy * c
        // A generous minimum: a lamp's footprint is smaller than a fingertip.
        let halfWidth = max(projection.length(proposal.size.x) / 2, 22)
        let halfDepth = max(projection.length(proposal.size.z) / 2, 22)
        return abs(CGFloat(localX)) <= halfWidth && abs(CGFloat(localY)) <= halfDepth
    }

    // MARK: - Drawing

    private func drawProposals(in context: GraphicsContext, using projection: PlanProjection) {
        for proposal in proposals {
            let centre = projection.point(proposal.position)
            let box = CGRect(x: -projection.length(proposal.size.x) / 2,
                             y: -projection.length(proposal.size.z) / 2,
                             width: projection.length(proposal.size.x),
                             height: projection.length(proposal.size.z))
            let isSelected = proposal.id == selection
            let link = links[proposal.id]
            // A product shows the colour its box gets in the model's picture.
            let tint = link.map { $0.marker?.color ?? .gray } ?? .green

            context.drawLayer { layer in
                layer.translateBy(x: centre.x, y: centre.y)
                layer.rotate(by: .radians(Double(proposal.rotation)))
                let path = Path(roundedRect: box, cornerRadius: 3)
                layer.fill(path, with: .color(tint.opacity(isSelected ? 0.42 : 0.24)))
                layer.stroke(path, with: .color(tint),
                             style: StrokeStyle(lineWidth: isSelected ? 3 : 1.5))

                // A notch on the front edge, so rotation is readable at a glance.
                var front = Path()
                front.move(to: CGPoint(x: box.minX, y: box.minY))
                front.addLine(to: CGPoint(x: box.maxX, y: box.minY))
                layer.stroke(front, with: .color(tint), lineWidth: isSelected ? 5 : 3)
            }

            guard let link else {
                context.draw(Text(proposal.kind.label).font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.green), at: centre)
                continue
            }
            drawLabel(of: link, at: centre, room: min(box.width, box.height), in: context)
        }
    }

    /// The product's picture when the piece is big enough on screen to hold it, and its name.
    private func drawLabel(of link: ProductLink, at centre: CGPoint, room: CGFloat,
                           in context: GraphicsContext) {
        let name = link.name.count > 20 ? link.name.prefix(19) + "…" : link.name
        let text = Text(name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.primary)
        guard let thumbnail = link.thumbnail, room >= 34 else {
            context.draw(text, at: centre)
            return
        }
        let side = min(room - 10, 40)
        let picture = context.resolve(Image(uiImage: thumbnail))
        let scale = side / max(picture.size.width, picture.size.height, 1)
        let size = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
        context.draw(picture, in: CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2 - 6,
                                         width: size.width, height: size.height))
        context.draw(text, at: CGPoint(x: centre.x, y: centre.y + size.height / 2 + 2))
    }

    /// A numbered square where each photo was taken, with a wedge the way it faced.
    private func drawPhotoSpots(in context: GraphicsContext, using projection: PlanProjection) {
        for (index, spot) in photoSpots.enumerated() {
            guard let spot else { continue }
            let centre = projection.point(spot.position)
            let tint = index == activeSpot ? Color.accentColor : Color(white: 0.3)

            var wedge = Path()
            wedge.move(to: centre)
            wedge.addArc(center: centre, radius: max(projection.length(0.8), 30),
                         startAngle: .radians(Double(spot.yaw - spot.fieldOfView / 2) - .pi / 2),
                         endAngle: .radians(Double(spot.yaw + spot.fieldOfView / 2) - .pi / 2),
                         clockwise: false)
            wedge.closeSubpath()
            context.fill(wedge, with: .color(tint.opacity(0.12)))
            context.stroke(wedge, with: .color(tint.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

            let badge = Path(roundedRect: CGRect(x: centre.x - 10, y: centre.y - 10, width: 20, height: 20),
                             cornerRadius: 5)
            context.fill(badge, with: .color(tint))
            context.stroke(badge, with: .color(.white), lineWidth: 1.5)
            context.draw(Text("\(index + 1)").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white), at: centre)
        }
    }

    private func drawCamera(in context: GraphicsContext, using projection: PlanProjection) {
        let centre = projection.point(position)
        let reach = projection.length(coneLength)

        var cone = Path()
        cone.move(to: centre)
        cone.addArc(center: centre, radius: reach,
                    startAngle: .radians(Double(yaw - fieldOfView / 2) - .pi / 2),
                    endAngle: .radians(Double(yaw + fieldOfView / 2) - .pi / 2),
                    clockwise: false)
        cone.closeSubpath()
        context.fill(cone, with: .color(.accentColor.opacity(0.22)))
        context.stroke(cone, with: .color(.accentColor.opacity(0.55)), lineWidth: 1)

        let body = CGRect(x: centre.x - 11, y: centre.y - 11, width: 22, height: 22)
        context.fill(Circle().path(in: body), with: .color(.accentColor))
        context.stroke(Circle().path(in: body), with: .color(.white), lineWidth: 2.5)

        let handle = projection.point(handlePosition())
        var stem = Path()
        stem.move(to: centre)
        stem.addLine(to: handle)
        context.stroke(stem, with: .color(.accentColor),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

        let knob = CGRect(x: handle.x - 9, y: handle.y - 9, width: 18, height: 18)
        context.fill(Circle().path(in: knob), with: .color(.white))
        context.stroke(Circle().path(in: knob), with: .color(.accentColor), lineWidth: 2.5)
    }
}
