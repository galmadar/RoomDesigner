import CoreGraphics
import simd

/// Maps between room metres and screen points, both ways.
///
/// Shared so the plan and anything drawn on top of it — the camera marker, its
/// view cone — agree about where things are.
struct PlanProjection {
    let low: SIMD2<Float>
    let scale: CGFloat
    let origin: CGPoint

    /// Zoom is applied about `focus`, which stays pinned to the middle of the
    /// view — so whatever you are working on cannot scroll off the edge.
    var zoom: CGFloat = 1
    var focus: SIMD2<Float>?
    private var viewCentre: CGPoint = .zero

    init?(plan: FloorPlan, size: CGSize, inset: CGFloat = 24,
          zoom: CGFloat = 1, focus: SIMD2<Float>? = nil) {
        let (low, high) = plan.bounds
        let extent = high - low
        guard extent.x > 0, extent.y > 0,
              size.width > inset * 2, size.height > inset * 2 else { return nil }

        let scale = min((size.width - inset * 2) / CGFloat(extent.x),
                        (size.height - inset * 2) / CGFloat(extent.y))
        let drawn = CGSize(width: CGFloat(extent.x) * scale, height: CGFloat(extent.y) * scale)

        self.low = low
        self.scale = scale
        self.origin = CGPoint(x: (size.width - drawn.width) / 2,
                              y: (size.height - drawn.height) / 2)
        self.zoom = zoom
        self.focus = focus
        self.viewCentre = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func unzoomed(_ position: SIMD2<Float>) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(position.x - low.x) * scale,
                y: origin.y + CGFloat(position.y - low.y) * scale)
    }

    func point(_ position: SIMD2<Float>) -> CGPoint {
        let flat = unzoomed(position)
        guard zoom != 1, let focus else { return flat }
        let anchor = unzoomed(focus)
        return CGPoint(x: viewCentre.x + (flat.x - anchor.x) * zoom,
                       y: viewCentre.y + (flat.y - anchor.y) * zoom)
    }

    func position(_ point: CGPoint) -> SIMD2<Float> {
        var flat = point
        if zoom != 1, let focus {
            let anchor = unzoomed(focus)
            flat = CGPoint(x: anchor.x + (point.x - viewCentre.x) / zoom,
                           y: anchor.y + (point.y - viewCentre.y) / zoom)
        }
        return SIMD2(low.x + Float((flat.x - origin.x) / scale),
                     low.y + Float((flat.y - origin.y) / scale))
    }

    func length(_ metres: Float) -> CGFloat { CGFloat(metres) * scale * zoom }
}
