import RoomPlan
import simd

/// What the scan actually knows about the room, in the shape the suggestion
/// service asks for.
///
/// Every field is optional and nil ones are left out of the JSON: a half-done
/// scan should still be able to ask for ideas, and a measurement invented to
/// fill a gap would be worse than none.
struct RoomFacts: Encodable {
    let kind: String?
    let width: Float?
    let length: Float?
    let height: Float?
    let objects: [String]?
    let windows: Int?
    let doors: Int?

    init(room: CapturedRoom) {
        let names = room.objects.compactMap { Self.name(of: $0.category) }
        let ordered = Self.deduped(names)
        objects = ordered.isEmpty ? nil : ordered
        kind = Self.kind(from: Set(ordered))
        windows = room.windows.count
        doors = room.doors.count
        height = room.walls.map(\.dimensions.y).max().map(Self.rounded)

        let bounds = FloorPlan(room: room).bounds
        let extent = bounds.max - bounds.min
        let sides = [abs(extent.x), abs(extent.y)].sorted()
        guard sides[1].isFinite, sides[0] > 0.1 else {
            width = nil
            length = nil
            return
        }
        // Whichever way the scan happened to lie, the shorter side is the width.
        width = Self.rounded(sides[0])
        length = Self.rounded(sides[1])
    }

    // MARK: -

    /// Deduped, commonest first, so the furniture that defines the room leads.
    private static func deduped(_ names: [String]) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for name in names {
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.sorted { left, right in
            let a = counts[left] ?? 0, b = counts[right] ?? 0
            return a == b ? left < right : a > b
        }
    }

    /// RoomPlan's own vocabulary, lowercased. Not `FloorPlan`'s labels: those
    /// are shortened for drawing on a plan ("TV", "Fridge") and the service is
    /// better served by the category names themselves.
    private static func name(of category: CapturedRoom.Object.Category) -> String? {
        switch category {
        case .bathtub: return "bathtub"
        case .bed: return "bed"
        case .chair: return "chair"
        case .dishwasher: return "dishwasher"
        case .fireplace: return "fireplace"
        case .oven: return "oven"
        case .refrigerator: return "refrigerator"
        case .sink: return "sink"
        case .sofa: return "sofa"
        case .stairs: return "stairs"
        case .storage: return "storage"
        case .stove: return "stove"
        case .table: return "table"
        case .television: return "television"
        case .toilet: return "toilet"
        case .washerDryer: return "washer dryer"
        @unknown default: return nil
        }
    }

    /// RoomPlan has no room-type field, so it is read off the furniture. Ordered
    /// by how decisive each piece is; nothing decisive means nil rather than a
    /// guess the service would then design around.
    private static func kind(from objects: Set<String>) -> String? {
        if objects.contains("bed") { return "bedroom" }
        if objects.contains("toilet") || objects.contains("bathtub") { return "bathroom" }
        if !objects.isDisjoint(with: ["stove", "oven", "dishwasher", "refrigerator"]) {
            return "kitchen"
        }
        if objects.contains("sofa") || objects.contains("television") { return "living room" }
        if objects.contains("table") && objects.contains("chair") { return "dining room" }
        return nil
    }

    private static func rounded(_ metres: Float) -> Float {
        (metres * 100).rounded() / 100
    }
}
