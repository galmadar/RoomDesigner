import RoomPlan
import simd

/// The scan as line segments in world space, for drawing over a photo.
enum ScanOutlines {
    enum Kind { case wall, floor, door, window, object }

    struct Edge {
        var start: SIMD3<Float>
        var end: SIMD3<Float>
        var kind: Kind
    }

    /// Objects first, so the walls — what is being checked — draw on top.
    static func edges(of room: CapturedRoom) -> [Edge] {
        room.objects.flatMap(box)
            + room.floors.flatMap { outline($0, .floor) }
            + room.walls.flatMap { outline($0, .wall) }
            + room.doors.flatMap { outline($0, .door) }
            + room.windows.flatMap { outline($0, .window) }
    }

    /// Same reading of a surface as `RoomGeometry`: `polygonCorners` in the
    /// surface's own plane, `dimensions` as the rectangular fallback.
    private static func outline(_ surface: CapturedRoom.Surface, _ kind: Kind) -> [Edge] {
        var corners = surface.polygonCorners.map { SIMD2($0.x, $0.y) }
        if corners.count < 3 {
            let half = SIMD2(surface.dimensions.x, surface.dimensions.y) / 2
            corners = [SIMD2(-half.x, -half.y), SIMD2(half.x, -half.y),
                       SIMD2(half.x, half.y), SIMD2(-half.x, half.y)]
        }
        let points = corners.map { (surface.transform * SIMD4($0.x, $0.y, 0, 1)).xyz }
        return points.indices.map {
            Edge(start: points[$0], end: points[($0 + 1) % points.count], kind: kind)
        }
    }

    private static func box(_ object: CapturedRoom.Object) -> [Edge] {
        let half = object.dimensions / 2
        let corners = (0..<8).map { index -> SIMD3<Float> in
            let sign = SIMD3<Float>(index & 1 == 0 ? -1 : 1,
                                    index & 2 == 0 ? -1 : 1,
                                    index & 4 == 0 ? -1 : 1)
            return (object.transform * SIMD4(half * sign, 1)).xyz
        }
        // Corners differing in exactly one bit share an edge.
        return (0..<8).flatMap { a in
            [1, 2, 4].compactMap { bit in
                a & bit == 0 ? Edge(start: corners[a], end: corners[a | bit], kind: .object) : nil
            }
        }
    }
}
