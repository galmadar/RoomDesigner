import simd

/// Measurements taken off the plan, for the offers a size correction makes.
///
/// "To the corner" and "against a wall" are only meaningful as distances to the
/// room's own walls, so they are measured rather than guessed — which is the
/// whole reason the scan is worth having.
enum PlanMeasure {

    /// How far a ray from `point` travels before it meets a wall.
    ///
    /// Walls are segments, so this is the nearest forward intersection; nil
    /// when the ray leaves the room without crossing one, which a scan with a
    /// gap in its walls can genuinely do.
    static func distanceToWall(from point: SIMD2<Float>,
                               along direction: SIMD2<Float>,
                               in plan: FloorPlan) -> Float? {
        var nearest: Float?
        for wall in plan.walls {
            guard let hit = intersection(origin: point, direction: direction,
                                         start: wall.start, end: wall.end) else { continue }
            // A hair forward, so a box already touching a wall is not measured to itself.
            guard hit > 0.01 else { continue }
            nearest = min(nearest ?? hit, hit)
        }
        return nearest
    }

    /// The shortest distance from a point to any wall, however it is turned.
    static func nearestWallDistance(to point: SIMD2<Float>, in plan: FloorPlan) -> Float? {
        var nearest: Float?
        for wall in plan.walls {
            let distance = distance(from: point, toSegment: wall.start, wall.end)
            nearest = min(nearest ?? distance, distance)
        }
        return nearest
    }

    // MARK: -

    private static func intersection(origin: SIMD2<Float>, direction: SIMD2<Float>,
                                     start: SIMD2<Float>, end: SIMD2<Float>) -> Float? {
        let segment = end - start
        let denominator = direction.x * segment.y - direction.y * segment.x
        guard abs(denominator) > 1e-6 else { return nil }     // parallel
        let offset = start - origin
        let alongRay = (offset.x * segment.y - offset.y * segment.x) / denominator
        let alongSegment = (offset.x * direction.y - offset.y * direction.x) / denominator
        guard (0...1).contains(alongSegment) else { return nil }
        return alongRay
    }

    private static func distance(from point: SIMD2<Float>,
                                 toSegment start: SIMD2<Float>,
                                 _ end: SIMD2<Float>) -> Float {
        let segment = end - start
        let lengthSquared = simd_length_squared(segment)
        guard lengthSquared > 1e-9 else { return simd_distance(point, start) }
        let t = simd_clamp(simd_dot(point - start, segment) / lengthSquared, 0, 1)
        return simd_distance(point, start + segment * t)
    }
}
