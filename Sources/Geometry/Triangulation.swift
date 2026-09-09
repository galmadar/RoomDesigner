import simd

/// Turning flat outlines into triangles.
enum Triangulation {

    /// Ear clipping for a simple polygon with no holes. Good enough here:
    /// RoomPlan outlines are a handful of corners, not thousands.
    static func earClip(_ polygon: [SIMD2<Float>]) -> [UInt32] {
        guard polygon.count >= 3 else { return [] }
        if polygon.count == 3 { return [0, 1, 2] }

        // Work anticlockwise so the convexity test has a fixed sense.
        var remaining = Array(polygon.indices)
        if signedArea(polygon) < 0 { remaining.reverse() }

        var triangles: [UInt32] = []
        var guardCounter = remaining.count * remaining.count

        while remaining.count > 3 && guardCounter > 0 {
            guardCounter -= 1
            var clipped = false

            for position in remaining.indices {
                let previous = remaining[(position + remaining.count - 1) % remaining.count]
                let current = remaining[position]
                let next = remaining[(position + 1) % remaining.count]

                let a = polygon[previous], b = polygon[current], c = polygon[next]
                guard cross(b - a, c - b) > 0 else { continue }          // reflex, not an ear

                let containsOther = remaining.contains { index in
                    index != previous && index != current && index != next
                        && pointInTriangle(polygon[index], a, b, c)
                }
                guard !containsOther else { continue }

                triangles.append(contentsOf: [UInt32(previous), UInt32(current), UInt32(next)])
                remaining.remove(at: position)
                clipped = true
                break
            }

            if !clipped { break }                                        // degenerate; bail out
        }

        if remaining.count == 3 {
            triangles.append(contentsOf: remaining.map(UInt32.init))
        }
        return triangles
    }

    /// A rectangle in a surface's local plane coordinates.
    struct Rect {
        var minX: Float, minY: Float, maxX: Float, maxY: Float

        var corners: [SIMD2<Float>] {
            [SIMD2(minX, minY), SIMD2(maxX, minY), SIMD2(maxX, maxY), SIMD2(minX, maxY)]
        }

        func intersects(_ other: Rect) -> Bool {
            minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
        }
    }

    /// Splits `bounds` into the rectangles left over once `holes` are removed.
    ///
    /// Slab decomposition: cut at every hole edge, then within each vertical
    /// slab emit the gaps between the holes covering it. Exact for rectangular
    /// walls with rectangular windows and doors, which is the ordinary case.
    static func subtracting(_ holes: [Rect], from bounds: Rect) -> [Rect] {
        let live = holes.filter { $0.intersects(bounds) }
        guard !live.isEmpty else { return [bounds] }

        var cuts: Set<Float> = [bounds.minX, bounds.maxX]
        for hole in live {
            cuts.insert(max(hole.minX, bounds.minX))
            cuts.insert(min(hole.maxX, bounds.maxX))
        }
        let columns = cuts.sorted()

        var result: [Rect] = []
        for index in 0..<(columns.count - 1) {
            let left = columns[index], right = columns[index + 1]
            guard right - left > 1e-5 else { continue }
            let middle = (left + right) / 2

            // Which holes span this slab, as y-intervals.
            var blocked = live
                .filter { $0.minX <= middle && $0.maxX >= middle }
                .map { (max($0.minY, bounds.minY), min($0.maxY, bounds.maxY)) }
                .sorted { $0.0 < $1.0 }

            // Merge overlapping intervals so the gaps between them are real.
            var merged: [(Float, Float)] = []
            for interval in blocked where interval.1 > interval.0 {
                if let last = merged.last, interval.0 <= last.1 {
                    merged[merged.count - 1].1 = max(last.1, interval.1)
                } else {
                    merged.append(interval)
                }
            }
            blocked = merged

            var cursor = bounds.minY
            for (low, high) in blocked {
                if low - cursor > 1e-5 {
                    result.append(Rect(minX: left, minY: cursor, maxX: right, maxY: low))
                }
                cursor = max(cursor, high)
            }
            if bounds.maxY - cursor > 1e-5 {
                result.append(Rect(minX: left, minY: cursor, maxX: right, maxY: bounds.maxY))
            }
        }
        return result
    }

    // MARK: -

    static func signedArea(_ polygon: [SIMD2<Float>]) -> Float {
        var total: Float = 0
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            total += a.x * b.y - b.x * a.y
        }
        return total / 2
    }

    private static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        a.x * b.y - a.y * b.x
    }

    private static func pointInTriangle(_ p: SIMD2<Float>, _ a: SIMD2<Float>,
                                        _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        let d1 = cross(b - a, p - a), d2 = cross(c - b, p - b), d3 = cross(a - c, p - c)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }
}
