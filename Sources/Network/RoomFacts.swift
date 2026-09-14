import RoomPlan
import simd

/// What the scan actually knows about the room, in the shape the suggestion
/// service asks for.
///
/// Every field is optional and nil ones are left out of the JSON: a half-done
/// scan should still be able to ask for ideas, and a measurement invented to
/// fill a gap would be worse than none.
///
/// What the *user* knows outranks the scan. Both the room type and every object
/// name here come from ``RoomReading``, so a wardrobe the scanner called a
/// refrigerator is described to the service as a wardrobe — and stops the room
/// being described as a kitchen.
struct RoomFacts: Encodable {
    let kind: String?
    let width: Float?
    let length: Float?
    let height: Float?
    let objects: [String]?
    let windows: Int?
    let doors: Int?

    init(room: CapturedRoom, corrections: RoomCorrections = .none) {
        self.init(reading: RoomReading(room: room, corrections: corrections), of: room)
    }

    init(reading: RoomReading, of room: CapturedRoom) {
        let ordered = reading.orderedNames
        objects = ordered.isEmpty ? nil : ordered
        kind = reading.kind
        windows = room.windows.count
        doors = room.doors.count
        height = room.walls.map(\.dimensions.y).max().map(Self.rounded)

        let bounds = FloorPlan(room: room, reading: reading).bounds
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

    /// RoomPlan's own vocabulary, lowercased. Not `FloorPlan`'s labels: those
    /// are shortened for drawing on a plan ("TV", "Fridge") and the service is
    /// better served by the category names themselves.
    ///
    /// A correction outranks the category, so this is only ever the fallback
    /// for an object the user has not contradicted — ``RoomReading`` is what
    /// decides which of the two applies.
    static func name(of category: CapturedRoom.Object.Category) -> String? {
        ObjectVocabulary.term(of: category).name
    }

    /// The room type read off the furniture, corrections first.
    static func kind(from reading: RoomReading) -> String? { reading.kind }

    private static func rounded(_ metres: Float) -> Float {
        (metres * 100).rounded() / 100
    }
}

extension RoomInterpretation.Request.Room {
    /// The room as the sentence-understanding endpoint wants it: corrected
    /// names and corrected boxes, so the service argues with what is on screen
    /// rather than with what the scanner originally said.
    init(reading: RoomReading, facts: RoomFacts) {
        self.init(kind: reading.kind,
                  widthMetres: facts.width,
                  lengthMetres: facts.length,
                  objects: reading.objects.map {
                      RoomInterpretation.Request.Object(
                          id: $0.id.uuidString,
                          category: $0.name,
                          widthMetres: $0.dimensions.x,
                          depthMetres: $0.dimensions.z,
                          heightMetres: $0.dimensions.y)
                  })
    }
}
