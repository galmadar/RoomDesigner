import SwiftUI
import simd

/// The floor plan as an instrument: stand somewhere and point, or place
/// furniture that isn't there yet.
///
/// One canvas, two modes. Mixing them on a phone-sized plan meant every camera
/// drag risked grabbing a sofa, so the mode is explicit rather than inferred.
struct CameraPlanPicker: View {
    enum Mode { case camera, furniture }

    let plan: FloorPlan
    var mode: Mode = .camera

    @Binding var position: SIMD2<Float>
    @Binding var yaw: Float
    @Binding var isDragging: Bool
    @Binding var fieldOfView: Float

    @Binding var proposals: [Proposal]
    @Binding var selection: Proposal.ID?

    @State private var grabbed: Grab?

    private enum Grab: Equatable { case body, direction, proposal(Proposal.ID) }

    private var coneLength: Float { 2.2 }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let projection = PlanProjection(plan: plan, size: size) else { return }
                FloorPlanView.draw(plan, in: context, using: projection, labels: true)
                drawProposals(in: context, using: projection)
                drawCamera(in: context, using: projection, dimmed: mode == .furniture)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let projection = PlanProjection(plan: plan, size: geometry.size)
                        else { return }
                        isDragging = true
                        update(with: value.location, projection: projection)
                    }
                    .onEnded { _ in
                        grabbed = nil
                        isDragging = false
                    }
            )
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Interaction

    private func direction() -> SIMD2<Float> { SIMD2(sin(yaw), -cos(yaw)) }
    private func handlePosition() -> SIMD2<Float> { position + direction() * coneLength }

    private func update(with location: CGPoint, projection: PlanProjection) {
        // Decide once per drag what was grabbed, so a fast finger cannot slip
        // from turning the camera to dragging a chair halfway through.
        if grabbed == nil { grabbed = grab(at: location, projection: projection) }

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

        case nil:
            break
        }
    }

    private func grab(at location: CGPoint, projection: PlanProjection) -> Grab {
        if mode == .furniture {
            // Topmost first, so a piece dropped on another can be picked up again.
            for proposal in proposals.reversed() where contains(proposal, location, projection) {
                selection = proposal.id
                return .proposal(proposal.id)
            }
            selection = nil
            return .body
        }

        let handle = projection.point(handlePosition())
        let toHandle = hypot(location.x - handle.x, location.y - handle.y)
        let body = projection.point(position)
        let toBody = hypot(location.x - body.x, location.y - body.y)
        return toHandle < toBody && toHandle < 60 ? .direction : .body
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

            context.drawLayer { layer in
                layer.translateBy(x: centre.x, y: centre.y)
                layer.rotate(by: .radians(Double(proposal.rotation)))
                let path = Path(roundedRect: box, cornerRadius: 3)
                layer.fill(path, with: .color(.green.opacity(isSelected ? 0.42 : 0.24)))
                layer.stroke(path, with: .color(.green),
                             style: StrokeStyle(lineWidth: isSelected ? 3 : 1.5))

                // A notch on the front edge, so rotation is readable at a glance.
                var front = Path()
                front.move(to: CGPoint(x: box.minX, y: box.minY))
                front.addLine(to: CGPoint(x: box.maxX, y: box.minY))
                layer.stroke(front, with: .color(.green), lineWidth: isSelected ? 5 : 3)
            }

            context.draw(Text(proposal.kind.label).font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green), at: centre)
        }
    }

    private func drawCamera(in context: GraphicsContext, using projection: PlanProjection,
                            dimmed: Bool) {
        let fade = dimmed ? 0.35 : 1.0
        let centre = projection.point(position)
        let reach = projection.length(coneLength)

        var cone = Path()
        cone.move(to: centre)
        cone.addArc(center: centre, radius: reach,
                    startAngle: .radians(Double(yaw - fieldOfView / 2) - .pi / 2),
                    endAngle: .radians(Double(yaw + fieldOfView / 2) - .pi / 2),
                    clockwise: false)
        cone.closeSubpath()
        context.fill(cone, with: .color(.accentColor.opacity(0.22 * fade)))
        context.stroke(cone, with: .color(.accentColor.opacity(0.55 * fade)), lineWidth: 1)

        let body = CGRect(x: centre.x - 11, y: centre.y - 11, width: 22, height: 22)
        context.fill(Circle().path(in: body), with: .color(.accentColor.opacity(fade)))
        context.stroke(Circle().path(in: body), with: .color(.white.opacity(fade)), lineWidth: 2.5)

        guard !dimmed else { return }

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
