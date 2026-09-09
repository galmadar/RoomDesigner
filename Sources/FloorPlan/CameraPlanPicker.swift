import SwiftUI
import simd

/// Stand somewhere in the room and point.
///
/// Replaces a bare 0-360 slider, which told you a number but not what you were
/// looking at. Here the plan you already have *is* the control: drag the marker
/// to move, drag the handle to turn, and the cone shows exactly what lands in
/// the picture.
struct CameraPlanPicker: View {
    let plan: FloorPlan

    @Binding var position: SIMD2<Float>
    @Binding var yaw: Float
    @Binding var isDragging: Bool

    /// Matches the renderer, so the cone shows the true frame.
    var fieldOfView: Float = 65 * .pi / 180

    @State private var dragging: Handle?

    private enum Handle { case body, direction }

    private var coneLength: Float { 2.2 }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let projection = PlanProjection(plan: plan, size: size) else { return }
                FloorPlanView.draw(plan, in: context, using: projection, labels: true)
                drawCamera(in: context, using: projection)
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
                        dragging = nil
                        isDragging = false
                    }
            )
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: -

    private func direction() -> SIMD2<Float> { SIMD2(sin(yaw), -cos(yaw)) }

    private func handlePosition() -> SIMD2<Float> { position + direction() * coneLength }

    private func update(with location: CGPoint, projection: PlanProjection) {
        // Decide once per drag which handle was grabbed, so a fast drag can't
        // jump from turning to moving halfway through.
        if dragging == nil {
            let toHandle = hypot(location.x - projection.point(handlePosition()).x,
                                 location.y - projection.point(handlePosition()).y)
            let toBody = hypot(location.x - projection.point(position).x,
                               location.y - projection.point(position).y)
            dragging = toHandle < toBody && toHandle < 60 ? .direction : .body
        }

        switch dragging {
        case .direction:
            let centre = projection.point(position)
            let dx = location.x - centre.x
            let dy = location.y - centre.y
            guard hypot(dx, dy) > 4 else { return }
            yaw = atan2(Float(dx), Float(-dy))
        case .body, nil:
            position = projection.position(location)
        }
    }

    private func drawCamera(in context: GraphicsContext, using projection: PlanProjection) {
        let centre = projection.point(position)
        let reach = projection.length(coneLength)

        // The cone: what actually ends up in the picture.
        var cone = Path()
        cone.move(to: centre)
        cone.addArc(center: centre,
                    radius: reach,
                    startAngle: .radians(Double(yaw - fieldOfView / 2) - .pi / 2),
                    endAngle: .radians(Double(yaw + fieldOfView / 2) - .pi / 2),
                    clockwise: false)
        cone.closeSubpath()
        context.fill(cone, with: .color(.accentColor.opacity(0.22)))
        context.stroke(cone, with: .color(.accentColor.opacity(0.55)), lineWidth: 1)

        // Where you stand.
        let body = CGRect(x: centre.x - 11, y: centre.y - 11, width: 22, height: 22)
        context.fill(Circle().path(in: body), with: .color(.accentColor))
        context.stroke(Circle().path(in: body), with: .color(.white), lineWidth: 2.5)

        // The handle you turn.
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
