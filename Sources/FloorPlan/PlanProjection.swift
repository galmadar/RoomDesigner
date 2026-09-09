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

    init?(plan: FloorPlan, size: CGSize, inset: CGFloat = 24) {
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
    }

    func point(_ position: SIMD2<Float>) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(position.x - low.x) * scale,
                y: origin.y + CGFloat(position.y - low.y) * scale)
    }

    func position(_ point: CGPoint) -> SIMD2<Float> {
        SIMD2(low.x + Float((point.x - origin.x) / scale),
              low.y + Float((point.y - origin.y) / scale))
    }

    func length(_ metres: Float) -> CGFloat { CGFloat(metres) * scale }
}
