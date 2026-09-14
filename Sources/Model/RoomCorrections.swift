import Foundation
import RoomPlan
import simd

/// What the user has said about a room that the scan got wrong.
///
/// RoomPlan decides a room's furniture during its post-processing pass and the
/// answer arrives already fixed. Rescanning is not a fix — the same closet, the
/// same shape, the same classifier gives the same refrigerator back — so the
/// only way out is to let the room be argued with and to keep what was said.
struct RoomCorrections: Codable, Hashable {

    /// Free text rather than an enum, deliberately: "guest room" is not a type
    /// any classifier can produce, and it is exactly the answer people give.
    var roomKind: String?

    /// What the room was called before, and when it changed — so the screen can
    /// say "was kitchen, a moment ago", offer Undo, and work out which pictures
    /// were made back when it was still a kitchen.
    var previousRoomKind: String?
    var roomKindSetAt: Date?

    /// Keyed by the scanned object's own identifier, as a string so the stored
    /// JSON stays readable rather than a flat array of alternating pairs.
    private var objects: [String: ObjectCorrection] = [:]

    static let none = RoomCorrections()

    /// One scanned object the user has corrected. Every field is optional: a
    /// nil is "the scan was right about this", never "zero".
    struct ObjectCorrection: Codable, Hashable {
        /// Free text in the app's own vocabulary — "wardrobe", "cabinet".
        var category: String?
        var widthMetres: Float?
        var depthMetres: Float?
        var heightMetres: Float?
        /// How far the box's centre has moved, in room (x, z) metres.
        ///
        /// Dragging an edge has to leave the opposite edge where it was — a
        /// wardrobe against a wall that grew symmetrically would grow into the
        /// wall — and moving one edge of a centred box is a size change *and* a
        /// shift. Stored, so the mesh is built from the box the user drew.
        var centreShift: SIMD2<Float>?
        /// The scan found something that is not there at all.
        var isRemoved: Bool = false

        var isEmpty: Bool {
            category == nil && widthMetres == nil && depthMetres == nil
                && heightMetres == nil && centreShift == nil && !isRemoved
        }

        var correctsSize: Bool {
            widthMetres != nil || depthMetres != nil || heightMetres != nil
        }
    }

    subscript(id: UUID) -> ObjectCorrection {
        get { objects[id.uuidString] ?? ObjectCorrection() }
        set {
            // An emptied correction is removed rather than stored blank, so
            // "has the user touched this object" stays a simple question.
            if newValue.isEmpty { objects.removeValue(forKey: id.uuidString) }
            else { objects[id.uuidString] = newValue }
        }
    }

    var correctedObjectIDs: Set<UUID> {
        Set(objects.keys.compactMap(UUID.init(uuidString:)))
    }

    var correctedObjectCount: Int { objects.count }

    var isEmpty: Bool { roomKind == nil && objects.isEmpty }

    // MARK: - Rescanning

    /// A rescan produces new objects with new identifiers, so a correction that
    /// named an old one cannot be carried across: matching by position would be
    /// its own guess, and a wrong guess here silently rewrites the geometry the
    /// picture is built from. Object corrections are therefore dropped, and the
    /// room type — which is keyed to nothing and was typed in words — is kept.
    ///
    /// Nothing is deleted on rescan itself: this is applied where the scan is
    /// read, so a correction is only ever discarded once its object is
    /// genuinely gone, and `droppedObjectCount` is what the screen says out loud.
    func matched(to identifiers: Set<UUID>) -> RoomCorrections {
        var copy = self
        copy.objects = objects.filter { key, _ in
            UUID(uuidString: key).map(identifiers.contains) ?? false
        }
        return copy
    }

    func droppedObjectCount(against identifiers: Set<UUID>) -> Int {
        correctedObjectCount - matched(to: identifiers).correctedObjectCount
    }
}
