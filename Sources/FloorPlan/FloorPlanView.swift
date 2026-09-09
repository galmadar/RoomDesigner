import SwiftUI

/// Draws the plan to scale. The view box is the room itself, so every rectangle
/// on screen is in true proportion — a wall twice as long is drawn twice as long.
struct FloorPlanView: View {
    let plan: FloorPlan
    var showsLabels = true

    var body: some View {
        Canvas { context, size in
            guard let projection = PlanProjection(plan: plan, size: size) else { return }
            FloorPlanView.draw(plan, in: context, using: projection, labels: showsLabels)
        }
        .background(Color(.secondarySystemBackground))
    }

    /// Shared with the camera picker, which draws the same plan underneath its
    /// own controls.
    static func draw(_ plan: FloorPlan, in context: GraphicsContext,
                     using projection: PlanProjection, labels: Bool) {
        for footprint in plan.objects {
            let box = CGRect(x: -projection.length(footprint.size.x) / 2,
                             y: -projection.length(footprint.size.y) / 2,
                             width: projection.length(footprint.size.x),
                             height: projection.length(footprint.size.y))
            let centre = projection.point(footprint.centre)

            context.drawLayer { layer in
                layer.translateBy(x: centre.x, y: centre.y)
                layer.rotate(by: .radians(Double(footprint.rotation)))
                let path = Path(roundedRect: box, cornerRadius: 2)
                layer.fill(path, with: .color(.accentColor.opacity(0.15)))
                layer.stroke(path, with: .color(.accentColor), lineWidth: 1)
            }

            if labels {
                context.draw(Text(footprint.label).font(.system(size: 9)), at: centre)
            }
        }

        for wall in plan.walls {
            var path = Path()
            path.move(to: projection.point(wall.start))
            path.addLine(to: projection.point(wall.end))
            context.stroke(path, with: .color(.primary), lineWidth: 3)
        }

        // Openings are drawn over the wall so they read as gaps in it.
        for (segments, colour) in [(plan.doors, Color.orange), (plan.windows, Color.blue)] {
            for segment in segments {
                var path = Path()
                path.move(to: projection.point(segment.start))
                path.addLine(to: projection.point(segment.end))
                context.stroke(path, with: .color(colour), lineWidth: 4)
            }
        }
    }
}
