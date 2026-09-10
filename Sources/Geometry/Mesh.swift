import simd

/// Triangles ready for the renderer. Positions are in room space, metres, with
/// the floor near y = 0 — the same space `CapturedRoom` uses.
struct Mesh {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    /// A flat colour per vertex, so the room can be drawn as a room rather than
    /// only as depth. Never lit or textured — it just has to be recognisable.
    var colours: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    mutating func append(_ other: Mesh) {
        let offset = UInt32(positions.count)
        positions.append(contentsOf: other.positions)
        normals.append(contentsOf: other.normals)
        colours.append(contentsOf: other.colours)
        indices.append(contentsOf: other.indices.map { $0 + offset })
    }

    /// Adds a planar polygon, already triangulated, lifted into world space.
    mutating func append(polygon corners: [SIMD2<Float>],
                         triangles: [UInt32],
                         transform: simd_float4x4,
                         colour: SIMD3<Float> = Palette.wall) {
        let offset = UInt32(positions.count)
        let normal = simd_normalize((transform * SIMD4<Float>(0, 0, 1, 0)).xyz)

        for corner in corners {
            let world = transform * SIMD4<Float>(corner.x, corner.y, 0, 1)
            positions.append(world.xyz)
            normals.append(normal)
            colours.append(colour)
        }
        indices.append(contentsOf: triangles.map { $0 + offset })
    }

    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard let first = positions.first else { return (.zero, .zero) }
        return positions.dropFirst().reduce((first, first)) {
            (simd_min($0.0, $1), simd_max($0.1, $1))
        }
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
