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

    /// Zoom is about the middle of the view and `pan` slides the map after it.
    ///
    /// Both are the map's own state. They used to be one number and a `focus`
    /// point taken from whatever was being edited, which meant the ground moved
    /// whenever the thing standing on it did: dragging the camera re-anchored
    /// the world around its new position every frame, so the next frame read the
    /// same finger as a different spot and the camera ran away across the room.
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    private var viewCentre: CGPoint = .zero
    private var viewSize: CGSize = .zero
    /// The plan's own rectangle at zoom 1, which is what the pan is clamped against.
    private var planRect: CGRect = .zero

    init?(plan: FloorPlan, size: CGSize, inset: CGFloat = 24,
          zoom: CGFloat = 1, pan: CGSize = .zero) {
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
        self.pan = pan
        self.viewCentre = CGPoint(x: size.width / 2, y: size.height / 2)
        self.viewSize = size
        self.planRect = CGRect(origin: origin, size: drawn)
    }

    private func unzoomed(_ position: SIMD2<Float>) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(position.x - low.x) * scale,
                y: origin.y + CGFloat(position.y - low.y) * scale)
    }

    func point(_ position: SIMD2<Float>) -> CGPoint {
        let flat = unzoomed(position)
        return CGPoint(x: viewCentre.x + (flat.x - viewCentre.x) * zoom + pan.width,
                       y: viewCentre.y + (flat.y - viewCentre.y) * zoom + pan.height)
    }

    func position(_ point: CGPoint) -> SIMD2<Float> {
        let flat = CGPoint(x: viewCentre.x + (point.x - pan.width - viewCentre.x) / zoom,
                           y: viewCentre.y + (point.y - pan.height - viewCentre.y) / zoom)
        return SIMD2(low.x + Float((flat.x - origin.x) / scale),
                     low.y + Float((flat.y - origin.y) / scale))
    }

    func length(_ metres: Float) -> CGFloat { CGFloat(metres) * scale * zoom }

    // MARK: - Moving the map

    /// The pan that holds whatever is under `anchor` still while the zoom
    /// changes — which is what pinching about the point between two fingers
    /// means, and the one thing a map may never get wrong.
    func pan(zoomingTo newZoom: CGFloat, about anchor: CGPoint) -> CGSize {
        let ratio = newZoom / zoom
        return CGSize(width: (1 - ratio) * (anchor.x - viewCentre.x) + ratio * pan.width,
                      height: (1 - ratio) * (anchor.y - viewCentre.y) + ratio * pan.height)
    }

    /// Holds the room on screen: at least half of whichever is smaller — the
    /// drawn plan or the view itself — stays inside the view on each axis, at
    /// every zoom. So the plan can be pushed aside but never pushed away.
    func clamped(_ proposed: CGSize) -> CGSize {
        let drawn = CGRect(x: viewCentre.x + (planRect.minX - viewCentre.x) * zoom,
                           y: viewCentre.y + (planRect.minY - viewCentre.y) * zoom,
                           width: planRect.width * zoom, height: planRect.height * zoom)
        return CGSize(width: Self.hold(proposed.width, between: drawn.minX, and: drawn.maxX,
                                       within: viewSize.width),
                      height: Self.hold(proposed.height, between: drawn.minY, and: drawn.maxY,
                                        within: viewSize.height))
    }

    private static func hold(_ offset: CGFloat, between near: CGFloat, and far: CGFloat,
                             within view: CGFloat) -> CGFloat {
        let keep = min(far - near, view) / 2
        let lowest = keep - far                 // the far edge stays `keep` past the near edge
        let highest = view - keep - near        // and the near edge `keep` short of the far one
        guard lowest <= highest else { return (lowest + highest) / 2 }
        return min(max(offset, lowest), highest)
    }
}
