import SwiftUI
import simd

/// The plan, with the scanned furniture as the thing you act on.
///
/// `PlanBoard` exists for `room.proposals` — furniture the user placed. Scanned
/// objects are not in that array and were not selectable at all, which is why a
/// wrongly measured closet had nowhere for an edit to go.
/// This draws the same plan and makes the scan itself the subject.
struct ScannedPlanView: View {

    /// Which side of the box the handle drags. Height has no plan to drag on.
    enum Axis: String, CaseIterable, Identifiable {
        case width, depth, height
        var id: String { rawValue }

        var label: String {
            switch self {
            case .width: return "wide"
            case .depth: return "deep"
            case .height: return "tall"
            }
        }

        var isOnThePlan: Bool { self != .height }
    }

    /// Dragging an edge, with the opposite edge pinned.
    struct Resize {
        var axis: Axis
        /// Metres for the dragged axis, written live.
        var metres: Binding<Float>
        /// How far the centre has moved from where the scan put it.
        var shift: Binding<SIMD2<Float>>
        var onBegin: () -> Void = {}
    }

    let plan: FloorPlan
    /// The one object being talked about; everything else is drawn quietly.
    var focus: UUID?
    var onSelect: ((UUID) -> Void)?
    var resize: Resize?

    @Environment(\.roomAccent) private var accent
    @State private var isDragging = false

    private var focused: FloorPlan.Footprint? {
        plan.objects.first { $0.id == focus }
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let projection = PlanProjection(plan: plan, size: size) else { return }
                draw(in: context, using: projection)
            }
            .contentShape(Rectangle())
            .gesture(gesture(in: geometry.size))
        }
        .background(Paper.tint)
    }

    // MARK: - Interaction

    private func gesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let projection = PlanProjection(plan: plan, size: size) else { return }
                if !isDragging {
                    isDragging = true
                    resize?.onBegin()
                }
                if resize != nil, focused != nil {
                    drag(to: projection.position(value.location))
                } else if let onSelect, let hit = footprint(at: value.location, projection) {
                    onSelect(hit.id)
                }
            }
            .onEnded { _ in isDragging = false }
    }

    private func footprint(at point: CGPoint, _ projection: PlanProjection) -> FloorPlan.Footprint? {
        // Topmost first, so a box drawn over another can still be picked up.
        plan.objects.reversed().first { footprint in
            let centre = projection.point(footprint.centre)
            let dx = Float(point.x - centre.x), dy = Float(point.y - centre.y)
            let c = cos(-footprint.rotation), s = sin(-footprint.rotation)
            let localX = dx * c - dy * s, localY = dx * s + dy * c
            // A generous minimum: a lamp's footprint is smaller than a fingertip.
            let halfWidth = max(projection.length(footprint.size.x) / 2, 22)
            let halfDepth = max(projection.length(footprint.size.y) / 2, 22)
            return abs(CGFloat(localX)) <= halfWidth && abs(CGFloat(localY)) <= halfDepth
        }
    }

    /// The opposite edge stays exactly where it was: that is what "drag the
    /// edge" means, and a box against a wall must not grow into the wall.
    private func drag(to point: SIMD2<Float>) {
        guard let resize, let footprint = focused, resize.axis.isOnThePlan else { return }
        let direction = axisDirection(of: footprint, resize.axis)
        let current = resize.axis == .width ? footprint.size.x : footprint.size.y
        let anchor = footprint.centre - direction * (current / 2)

        let measured = simd_dot(point - anchor, direction)
        let settled = min(max(measured, 0.1), 6)
        resize.metres.wrappedValue = settled

        let centre = anchor + direction * (settled / 2)
        resize.shift.wrappedValue += centre - footprint.centre
    }

    private func axisDirection(of footprint: FloorPlan.Footprint, _ axis: Axis) -> SIMD2<Float> {
        let along = SIMD2(cos(footprint.rotation), sin(footprint.rotation))
        return axis == .width ? along : SIMD2(-along.y, along.x)
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, using projection: PlanProjection) {
        for footprint in plan.objects where footprint.id != focus {
            let box = rect(footprint.size, projection)
            context.drawLayer { layer in
                let centre = projection.point(footprint.centre)
                layer.translateBy(x: centre.x, y: centre.y)
                layer.rotate(by: .radians(Double(footprint.rotation)))
                let path = Path(roundedRect: box, cornerRadius: 3)
                layer.fill(path, with: .color(Paper.mutedInk.opacity(0.22)))
                layer.stroke(path, with: .color(Paper.mutedInk.opacity(0.55)), lineWidth: 1.5)
            }
            context.draw(Text(footprint.label).font(.system(size: 10))
                            .foregroundStyle(Paper.mutedInk),
                         at: projection.point(footprint.centre))
        }

        for wall in plan.walls {
            var path = Path()
            path.move(to: projection.point(wall.start))
            path.addLine(to: projection.point(wall.end))
            context.stroke(path, with: .color(Paper.ink), lineWidth: 3)
        }
        for (segments, colour) in [(plan.doors, Paper.mutedInk), (plan.windows, accent)] {
            for segment in segments {
                var path = Path()
                path.move(to: projection.point(segment.start))
                path.addLine(to: projection.point(segment.end))
                context.stroke(path, with: .color(colour.opacity(0.7)), lineWidth: 4)
            }
        }

        guard let footprint = focused else { return }
        drawFocus(footprint, in: context, using: projection)
    }

    private func drawFocus(_ footprint: FloorPlan.Footprint,
                           in context: GraphicsContext, using projection: PlanProjection) {
        let centre = projection.point(footprint.centre)

        // What the scan measured, so the change is visible as a change.
        if footprint.isCorrected {
            let direction = axisDirection(of: footprint, .width)
            let anchor = footprint.centre - direction * (footprint.size.x / 2)
            let scannedCentre = anchor + direction * (footprint.scannedSize.x / 2)
            context.drawLayer { layer in
                let point = projection.point(scannedCentre)
                layer.translateBy(x: point.x, y: point.y)
                layer.rotate(by: .radians(Double(footprint.rotation)))
                layer.stroke(Path(roundedRect: rect(footprint.scannedSize, projection),
                                  cornerRadius: 3),
                             with: .color(Paper.mutedInk.opacity(0.7)),
                             style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }

        context.drawLayer { layer in
            layer.translateBy(x: centre.x, y: centre.y)
            layer.rotate(by: .radians(Double(footprint.rotation)))
            let path = Path(roundedRect: rect(footprint.size, projection), cornerRadius: 4)
            layer.fill(path, with: .color(accent.opacity(0.18)))
            layer.stroke(path, with: .color(accent), lineWidth: 2.5)
        }

        guard let resize, resize.axis.isOnThePlan else { return }
        let direction = axisDirection(of: footprint, resize.axis)
        let extent = resize.axis == .width ? footprint.size.x : footprint.size.y
        let handle = projection.point(footprint.centre + direction * (extent / 2))
        let knob = CGRect(x: handle.x - 10, y: handle.y - 10, width: 20, height: 20)
        context.fill(Circle().path(in: knob), with: .color(Paper.card))
        context.stroke(Circle().path(in: knob), with: .color(accent), lineWidth: 2.5)

        // The live measurement, against the edge being dragged.
        let reading = Text("\(extent, format: .number.precision(.fractionLength(2))) m")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
        context.draw(reading, at: CGPoint(x: handle.x, y: handle.y - 26))
    }

    private func rect(_ size: SIMD2<Float>, _ projection: PlanProjection) -> CGRect {
        CGRect(x: -projection.length(size.x) / 2, y: -projection.length(size.y) / 2,
               width: projection.length(size.x), height: projection.length(size.y))
    }
}
