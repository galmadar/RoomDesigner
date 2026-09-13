import RoomPlan
import simd

/// How far RoomPlan's processed room sits from the AR session's world frame,
/// which is the frame photo poses are in.
///
/// Apple's multi-room guidance implies the two are one and the same; this
/// measures it per scan, from the walls both versions of the room share.
struct ScanAlignment {
    /// Carries AR-world coordinates into the processed room's.
    let correction: simd_float4x4
    let matchedWalls: Int
    /// Metres, across the floor.
    let offset: Float
    /// Radians, about the vertical.
    let turn: Float

    init?(live: CapturedRoom, processed: CapturedRoom) {
        let finals = Dictionary(processed.walls.map { ($0.identifier, $0) },
                                uniquingKeysWith: { first, _ in first })
        let pairs = live.walls.compactMap { wall in finals[wall.identifier].map { (wall, $0) } }
        guard pairs.count >= 2 else { return nil }

        // A wall's axis is only defined up to a half turn, hence `remainder`.
        let turn = Self.median(pairs.map { remainder(Self.heading($1) - Self.heading($0), .pi) })
        let c = cos(turn), s = sin(turn)
        func rotate(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x * c - p.z * s, p.y, p.x * s + p.z * c) }

        // Medians, because processing trims and extends walls along their length.
        let shifts = pairs.map { $1.transform.columns.3.xyz - rotate($0.transform.columns.3.xyz) }
        let shift = SIMD3(Self.median(shifts.map(\.x)), Self.median(shifts.map(\.y)),
                          Self.median(shifts.map(\.z)))

        correction = simd_float4x4(SIMD4(c, 0, s, 0), SIMD4(0, 1, 0, 0),
                                   SIMD4(-s, 0, c, 0), SIMD4(shift, 1))
        matchedWalls = pairs.count
        offset = simd_length(SIMD2(shift.x, shift.z))
        self.turn = turn
    }

    /// Small enough that no one could see it in a photo.
    var isNegligible: Bool { offset < 0.03 && abs(turn) < 0.5 * .pi / 180 }

    var summary: String {
        String(format: "Scan vs camera: %d walls matched, %.1f cm and %.1f° apart",
               matchedWalls, offset * 100, turn * 180 / .pi)
    }

    private static func heading(_ wall: CapturedRoom.Surface) -> Float {
        atan2(wall.transform.columns.0.z, wall.transform.columns.0.x)
    }

    private static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
