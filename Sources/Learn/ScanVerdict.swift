import RoomPlan
import simd

/// What can honestly be said about a finished scan, read from the scan itself.
///
/// Everything here is something RoomPlan reported: what it found, how sure it
/// says it is, and which wall edges it never closed. There is deliberately no
/// quality score — nothing in `CapturedRoom` would support one, and a number
/// nobody can defend is worse than a sentence that is true.
struct ScanVerdict {

    /// One wall, with what the scan left unfinished about it.
    struct WallState {
        /// The four edges minus the ones RoomPlan says it completed.
        let openEdges: Set<CapturedRoom.Surface.Edge>
        let confidence: CapturedRoom.Confidence
        /// Metres along the wall.
        let width: Float
    }

    let walls: Int
    let windows: Int
    let doors: Int
    let objects: Int
    let hasFloor: Bool

    /// Walls whose vertical edges RoomPlan never closed — it never joined them
    /// into their corners, which is exactly what sweeping quickly past a wall
    /// leaves behind.
    let unjoined: [WallState]

    /// Walls RoomPlan itself marks as less than high confidence.
    let unsure: [WallState]

    /// Total wall length as a fraction of the floor outline's perimeter, where
    /// both exist. Well under 1 means part of the room's edge has no wall.
    let perimeterCovered: Float?

    init(room: CapturedRoom) {
        walls = room.walls.count
        windows = room.windows.count
        doors = room.doors.count
        objects = room.objects.count
        hasFloor = room.floors.first != nil

        let measured = room.walls.map { wall in
            WallState(openEdges: Set(CapturedRoom.Surface.Edge.allCases)
                        .subtracting(wall.completedEdges),
                      confidence: wall.confidence,
                      width: wall.dimensions.x)
        }
        // Left and right are a wall's vertical edges: its corners. Top or bottom
        // open only means the full height was never seen, which matters far less
        // to a picture than a corner that was never joined.
        unjoined = measured.filter { !$0.openEdges.isDisjoint(with: [.left, .right]) }
        unsure = measured.filter { $0.confidence != .high }
        perimeterCovered = Self.coverage(of: room)
    }

    #if DEBUG
    /// Fabricated, for the stand-in harness only. Scanning needs a LiDAR device,
    /// so this is the only way to put the screen on a simulator at all.
    init(standInWalls: Int, windows: Int, doors: Int, objects: Int, unjoined open: Int) {
        walls = standInWalls
        self.windows = windows
        self.doors = doors
        self.objects = objects
        hasFloor = true
        let thin = WallState(openEdges: [.left], confidence: .medium, width: 3)
        self.unjoined = Array(repeating: thin, count: open)
        self.unsure = Array(repeating: thin, count: open)
        perimeterCovered = 1
    }
    #endif

    // MARK: - What it is allowed to say

    /// "4 walls, 1 window, 3 things" — counts only, which are never in doubt.
    var headline: String {
        var parts = [Self.count(walls, "wall"), Self.count(windows, "window")]
        if doors > 0 { parts.append(Self.count(doors, "door")) }
        parts.append(Self.count(objects, "thing"))
        return parts.joined(separator: ", ")
    }

    /// Worth offering a re-scan before any time is spent on this room.
    var isThin: Bool {
        !hasFloor || walls < 3 || !unjoined.isEmpty || (perimeterCovered ?? 1) < 0.7
    }

    /// Most damaging first. Every one of these names something measured.
    var concerns: [String] {
        var said: [String] = []

        if !hasFloor {
            said.append("No floor came out of this scan, so there is nothing to stand a picture on. This one is worth doing again.")
        } else if walls < 3 {
            said.append(walls == 0
                ? "No walls came out of this scan at all."
                : "Only \(Self.count(walls, "wall")) came out of this scan. A room needs its whole perimeter before a picture can hold together.")
        }

        if let covered = perimeterCovered, covered < 0.7 {
            let missing = Int(((1 - covered) * 100).rounded())
            said.append("About \(missing)% of the way round the room has no wall against it. Pictures looking that way have nothing to hold on to.")
        }

        if !unjoined.isEmpty {
            said.append(unjoined.count == 1
                ? "One wall never got joined into its corners — you passed it quickly. Pictures looking that way may drift. Two more minutes would fix it."
                : "\(unjoined.count) walls never got joined into their corners — you passed them quickly. Pictures looking that way may drift. Two more minutes would fix it.")
        } else if !unsure.isEmpty {
            said.append(unsure.count == 1
                ? "RoomPlan is less than sure about one of these walls."
                : "RoomPlan is less than sure about \(unsure.count) of these walls.")
        }

        return said
    }

    /// When nothing above fired, say so rather than saying nothing.
    var reassurance: String {
        "Every wall was joined into its corners. Nothing came out thin."
    }

    // MARK: -

    /// Total wall width against the floor outline's perimeter. Approximate —
    /// walls overlap at the corners and RoomPlan trims them — so it is only
    /// ever used to say a lot of the edge is missing, never to grade a scan.
    private static func coverage(of room: CapturedRoom) -> Float? {
        guard let floor = RoomFloor(room: room), floor.polygon.count >= 3 else { return nil }
        var perimeter: Float = 0
        for index in floor.polygon.indices {
            let next = floor.polygon[(index + 1) % floor.polygon.count]
            perimeter += simd_distance(floor.polygon[index], next)
        }
        guard perimeter > 0.5 else { return nil }
        let total = room.walls.reduce(Float(0)) { $0 + $1.dimensions.x }
        return total / perimeter
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}
