import Foundation
import RoomPlan
import simd

/// The scan as the app should read it: RoomPlan's measurements with whatever
/// the user has said about them already applied.
///
/// Everything that used to ask `CapturedRoom` directly what an object is or how
/// big it is asks this instead — the plan's labels, the facts sent to the
/// service, and the proxy mesh. That last one is the one that matters: the mesh
/// is what the conditioning image is rendered from, so a correction that does
/// not reach it has not worked.
struct RoomReading {

    /// One scanned object, as corrected.
    struct Object: Identifiable {
        var id: UUID
        var scanned: CapturedRoom.Object
        var term: ObjectVocabulary.Term
        /// What the box should actually be, in metres.
        var dimensions: SIMD3<Float>
        /// What RoomPlan measured, kept so a screen can say "0.6 m as scanned".
        var scannedDimensions: SIMD3<Float>
        var isCategoryCorrected: Bool
        var isSizeCorrected: Bool
        /// How far the corrected box's centre sits from the scanned one.
        var centreShift: SIMD2<Float>

        var name: String { term.name }
        var label: String { term.label }
        var category: CapturedRoom.Object.Category? { term.category }
        var isCorrected: Bool { isCategoryCorrected || isSizeCorrected }

        /// The scan's placement with the correction's shift applied. This, not
        /// `scanned.transform`, is where the box actually belongs.
        var transform: simd_float4x4 {
            var corrected = scanned.transform
            corrected.columns.3.x += centreShift.x
            corrected.columns.3.z += centreShift.y
            return corrected
        }

        /// Where it stands on the floor, in room coordinates (x, z).
        var groundPosition: SIMD2<Float> {
            SIMD2(transform.columns.3.x, transform.columns.3.z)
        }

        var scannedGroundPosition: SIMD2<Float> {
            SIMD2(scanned.transform.columns.3.x, scanned.transform.columns.3.z)
        }

        var yaw: Float {
            atan2(scanned.transform.columns.0.z, scanned.transform.columns.0.x)
        }
    }

    /// The room type read off the furniture, and what decided it.
    ///
    /// The reason is the whole point: "two tables, a sofa, four chairs and one
    /// refrigerator" is what turns a correction into a conversation, and the
    /// shaky object is the thing worth arguing with.
    struct Guess {
        var kind: String?
        /// The object that settled it, when a single one did.
        var decidedBy: UUID?
    }

    let corrections: RoomCorrections
    /// Objects the user has not struck out, in the scan's own order.
    let objects: [Object]
    let guess: Guess

    /// What the user said, and only failing that what the scan worked out.
    var kind: String? { corrections.roomKind ?? guess.kind }

    /// True when the room type on screen is the user's word rather than a guess.
    var isKindCorrected: Bool { corrections.roomKind != nil }

    init(room: CapturedRoom, corrections stored: RoomCorrections) {
        let identifiers = Set(room.objects.map(\.identifier))
        // Corrections whose object is gone are dropped here rather than at the
        // moment of a rescan, which this file never sees.
        let corrections = stored.matched(to: identifiers)
        self.corrections = corrections

        objects = room.objects.compactMap { scanned in
            let correction = corrections[scanned.identifier]
            guard !correction.isRemoved else { return nil }

            let term = correction.category.map(ObjectVocabulary.term(forCorrection:))
                ?? ObjectVocabulary.term(of: scanned.category)
            let measured = scanned.dimensions
            let dimensions = SIMD3(correction.widthMetres ?? measured.x,
                                   correction.heightMetres ?? measured.y,
                                   correction.depthMetres ?? measured.z)

            return Object(id: scanned.identifier,
                          scanned: scanned,
                          term: term,
                          dimensions: dimensions,
                          scannedDimensions: measured,
                          isCategoryCorrected: correction.category != nil,
                          isSizeCorrected: correction.correctsSize,
                          centreShift: correction.centreShift ?? .zero)
        }

        guess = Self.guess(from: objects)
    }

    // MARK: - Reading the room off its furniture

    /// RoomPlan has no room-type field, so it is read off the furniture.
    /// Ordered by how decisive each piece is; nothing decisive means nil rather
    /// than a guess the service would then design around.
    ///
    /// Unchanged from the inference this replaces, with one difference that is
    /// the entire point: it reads corrected names, so a wardrobe that was
    /// scanned as a refrigerator stops voting for a kitchen.
    private static func guess(from objects: [Object]) -> Guess {
        func first(_ names: Set<String>) -> Object? {
            objects.first { names.contains($0.name) }
        }

        if let found = first(["bed"]) {
            return Guess(kind: "bedroom", decidedBy: found.id)
        }
        if let found = first(["toilet", "bathtub"]) {
            return Guess(kind: "bathroom", decidedBy: found.id)
        }
        if let found = first(["stove", "oven", "dishwasher", "refrigerator"]) {
            return Guess(kind: "kitchen", decidedBy: found.id)
        }
        if let found = first(["sofa", "television"]) {
            return Guess(kind: "living room", decidedBy: found.id)
        }
        let names = Set(objects.map(\.name))
        if names.contains("table") && names.contains("chair") {
            return Guess(kind: "dining room", decidedBy: nil)
        }
        return Guess(kind: nil, decidedBy: nil)
    }

    // MARK: - Counting

    /// Deduped, commonest first, so the furniture that defines the room leads.
    var orderedNames: [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for name in objects.map(\.name) {
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.sorted { left, right in
            let a = counts[left] ?? 0, b = counts[right] ?? 0
            return a == b ? left < right : a > b
        }
    }

    /// "2 tables", "1 sofa" — what the scan found, as the guess screen lists it.
    var tally: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for name in objects.map(\.name) { counts[name, default: 0] += 1 }
        return orderedNames.map { ($0, counts[$0] ?? 0) }
    }

    func object(_ id: UUID) -> Object? { objects.first { $0.id == id } }
}
