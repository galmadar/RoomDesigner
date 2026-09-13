import RoomPlan
import simd

/// The scanned floor as a polygon in world (x, z), and the questions anyone
/// standing on it needs answered.
///
/// The bounding box is not the room. A room scanned at an angle has box corners
/// well outside its walls, so placing a camera from `bounds` can put it inside
/// one — looking at the back of a wall, which renders as a solid block.
struct RoomFloor {
    /// World (x, z), in the scan's own winding.
    let polygon: [SIMD2<Float>]
    /// World y of the floor.
    let level: Float
    /// World y of the top of the tallest wall.
    let ceiling: Float

    /// +1 when the outline winds so that the interior lies left of each edge.
    private let handedness: Float

    init?(room: CapturedRoom) {
        guard let floor = room.floors.first else { return nil }

        // The same reading of a surface as `RoomGeometry`: the real outline when
        // there is one, the rectangle from `dimensions` otherwise.
        var corners = floor.polygonCorners.map { SIMD2($0.x, $0.y) }
        if corners.count < 3 {
            let half = SIMD2(floor.dimensions.x, floor.dimensions.y) / 2
            corners = [SIMD2(-half.x, -half.y), SIMD2(half.x, -half.y),
                       SIMD2(half.x, half.y), SIMD2(-half.x, half.y)]
        }
        guard corners.count >= 3 else { return nil }

        polygon = corners.map { corner in
            let world = floor.transform * SIMD4<Float>(corner.x, corner.y, 0, 1)
            return SIMD2(world.x, world.z)
        }
        level = floor.transform.columns.3.y
        ceiling = room.walls.map { $0.transform.columns.3.y + $0.dimensions.y / 2 }.max()
            ?? (floor.transform.columns.3.y + 2.4)
        handedness = Triangulation.signedArea(polygon) > 0 ? 1 : -1
    }

    /// Ray crossing. Corners are few, so the plain test is the right one.
    func contains(_ point: SIMD2<Float>) -> Bool {
        var inside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            if (current.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - current.x) * (point.y - current.y)
                   / (previous.y - current.y) + current.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }

    /// Pushes a spot back until it stands at least `margin` inside every wall.
    ///
    /// Repeated because one push, taken in a corner, can cross the wall beside
    /// it; four passes settle every outline RoomPlan produces.
    func keepInside(_ point: SIMD2<Float>, margin: Float) -> SIMD2<Float> {
        var moved = point
        for _ in 0..<4 {
            let wall = nearestWall(to: moved)
            if contains(moved), wall.distance >= margin { return moved }
            moved = wall.closest + wall.inward * margin
        }
        return moved
    }

    /// The spot furthest from any wall: the middle of an L-shaped room's wider
    /// arm rather than the middle of its box, which can be outside the room.
    var deepestPoint: SIMD2<Float> {
        let low = polygon.reduce(polygon[0], simd_min)
        let high = polygon.reduce(polygon[0], simd_max)

        var best = (point: (low + high) / 2, clearance: -Float.greatestFiniteMagnitude)
        var origin = low
        var span = high - low
        // A coarse sweep, then two refinements around the winner.
        for _ in 0..<3 {
            let steps = 12
            for column in 0...steps {
                for row in 0...steps {
                    let candidate = origin + span * SIMD2(Float(column) / Float(steps),
                                                          Float(row) / Float(steps))
                    guard contains(candidate) else { continue }
                    let clearance = nearestWall(to: candidate).distance
                    if clearance > best.clearance { best = (candidate, clearance) }
                }
            }
            span /= 4
            origin = best.point - span / 2
        }
        return best.point
    }

    /// The longest sightline from a spot, so the room opens facing into itself
    /// rather than at the wall behind you.
    func heading(from point: SIMD2<Float>) -> Float {
        var farthest = polygon[0]
        var reach: Float = -1
        for corner in polygon {
            let distance = simd_distance(corner, point)
            if distance > reach { reach = distance; farthest = corner }
        }
        let direction = farthest - point
        guard simd_length(direction) > 1e-4 else { return 0 }
        return atan2(direction.x, -direction.y)
    }

    // MARK: -

    /// The closest point on the outline, which way the room lies from it, and how far.
    private func nearestWall(to point: SIMD2<Float>)
        -> (closest: SIMD2<Float>, inward: SIMD2<Float>, distance: Float) {
        var best = (closest: polygon[0], inward: SIMD2<Float>(0, 1),
                    distance: Float.greatestFiniteMagnitude)
        for index in polygon.indices {
            let start = polygon[index], end = polygon[(index + 1) % polygon.count]
            let along = end - start
            let lengthSquared = simd_length_squared(along)
            let position = lengthSquared > 1e-9
                ? simd_clamp(simd_dot(point - start, along) / lengthSquared, 0, 1) : 0
            let closest = start + along * position
            let distance = simd_distance(point, closest)
            guard distance < best.distance else { continue }
            // Left of the edge is inside, given the outline's winding.
            let direction = lengthSquared > 1e-9
                ? along / lengthSquared.squareRoot() : SIMD2<Float>(1, 0)
            best = (closest, SIMD2(-direction.y, direction.x) * handedness, distance)
        }
        return best
    }
}
