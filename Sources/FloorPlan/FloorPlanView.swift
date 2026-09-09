import SwiftUI

/// Draws the plan to scale. The view box is the room itself, so every rectangle
/// on screen is in true proportion — a wall twice as long is drawn twice as long.
struct FloorPlanView: View {
    let plan: FloorPlan

    var body: some View {
        Canvas { context, size in
            let (low, high) = plan.bounds
            let extent = high - low
            guard extent.x > 0, extent.y > 0 else { return }

            let inset: CGFloat = 24
            let scale = min((size.width - inset * 2) / CGFloat(extent.x),
                            (size.height - inset * 2) / CGFloat(extent.y))
            let drawn = CGSize(width: CGFloat(extent.x) * scale, height: CGFloat(extent.y) * scale)
            let origin = CGPoint(x: (size.width - drawn.width) / 2,
                                 y: (size.height - drawn.height) / 2)

            func place(_ point: SIMD2<Float>) -> CGPoint {
                CGPoint(x: origin.x + CGFloat(point.x - low.x) * scale,
                        y: origin.y + CGFloat(point.y - low.y) * scale)
            }

            for footprint in plan.objects {
                let box = CGRect(x: -CGFloat(footprint.size.x) * scale / 2,
                                 y: -CGFloat(footprint.size.y) * scale / 2,
                                 width: CGFloat(footprint.size.x) * scale,
                                 height: CGFloat(footprint.size.y) * scale)
                let centre = place(footprint.centre)

                context.drawLayer { layer in
                    layer.translateBy(x: centre.x, y: centre.y)
                    layer.rotate(by: .radians(Double(footprint.rotation)))
                    let path = Path(roundedRect: box, cornerRadius: 2)
                    layer.fill(path, with: .color(.accentColor.opacity(0.15)))
                    layer.stroke(path, with: .color(.accentColor), lineWidth: 1)
                }

                context.draw(Text(footprint.label).font(.system(size: 9)),
                             at: centre)
            }

            for wall in plan.walls {
                var path = Path()
                path.move(to: place(wall.start))
                path.addLine(to: place(wall.end))
                context.stroke(path, with: .color(.primary), lineWidth: 3)
            }

            // Openings are drawn over the wall so they read as gaps in it.
            for (segments, colour) in [(plan.doors, Color.orange), (plan.windows, Color.blue)] {
                for segment in segments {
                    var path = Path()
                    path.move(to: place(segment.start))
                    path.addLine(to: place(segment.end))
                    context.stroke(path, with: .color(colour), lineWidth: 4)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}
