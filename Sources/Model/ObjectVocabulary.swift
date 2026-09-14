import Foundation
import RoomPlan

/// The one place that answers "what kind of thing is this".
///
/// It used to be answered independently in three places — the plan's labels,
/// the facts sent to the service, and the proxy mesh's lookup key — which is
/// why a correction had nowhere to go. Everything now reads a `Term`, whether
/// it came from RoomPlan's classifier or from the user contradicting it.
enum ObjectVocabulary {

    struct Term: Hashable {
        /// RoomPlan's own vocabulary, lowercased — what the service is told.
        var name: String
        /// Shortened for drawing on a plan, where space is the constraint.
        var label: String
        /// The nearest RoomPlan category, which is what the proxy mesh library
        /// is keyed on. Nil for things RoomPlan has no category for at all.
        var category: CapturedRoom.Object.Category?
    }

    // MARK: - What the scan says

    static func term(of category: CapturedRoom.Object.Category) -> Term {
        switch category {
        case .bathtub: return Term(name: "bathtub", label: "Bath", category: .bathtub)
        case .bed: return Term(name: "bed", label: "Bed", category: .bed)
        case .chair: return Term(name: "chair", label: "Chair", category: .chair)
        case .dishwasher: return Term(name: "dishwasher", label: "Dishwasher", category: .dishwasher)
        case .fireplace: return Term(name: "fireplace", label: "Fireplace", category: .fireplace)
        case .oven: return Term(name: "oven", label: "Oven", category: .oven)
        case .refrigerator: return Term(name: "refrigerator", label: "Fridge", category: .refrigerator)
        case .sink: return Term(name: "sink", label: "Sink", category: .sink)
        case .sofa: return Term(name: "sofa", label: "Sofa", category: .sofa)
        case .stairs: return Term(name: "stairs", label: "Stairs", category: .stairs)
        case .storage: return Term(name: "storage", label: "Storage", category: .storage)
        case .stove: return Term(name: "stove", label: "Stove", category: .stove)
        case .table: return Term(name: "table", label: "Table", category: .table)
        case .television: return Term(name: "television", label: "TV", category: .television)
        case .toilet: return Term(name: "toilet", label: "Toilet", category: .toilet)
        case .washerDryer: return Term(name: "washer dryer", label: "Washer", category: .washerDryer)
        @unknown default: return Term(name: "object", label: "Object", category: nil)
        }
    }

    /// How a category is spelled in `CapturedRoom`'s own JSON, which is the
    /// case name: a Swift enum with no raw value encodes as `{"storage":{}}`.
    static func jsonKey(of category: CapturedRoom.Object.Category) -> String {
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
        case .washerDryer: return "washerDryer"
        @unknown default: return "storage"
        }
    }

    // MARK: - What the user says

    /// Everything a correction can name. Wider than RoomPlan's sixteen on
    /// purpose — a wardrobe is the whole reason this exists — and each one
    /// carries the nearest category so the proxy lookup still finds a shape.
    static let known: [Term] = [
        Term(name: "wardrobe", label: "Wardrobe", category: .storage),
        Term(name: "cabinet", label: "Cabinet", category: .storage),
        Term(name: "chest of drawers", label: "Drawers", category: .storage),
        Term(name: "shelf", label: "Shelf", category: .storage),
        Term(name: "bookcase", label: "Bookcase", category: .storage),
        Term(name: "cupboard", label: "Cupboard", category: .storage),
        Term(name: "desk", label: "Desk", category: .table),
        Term(name: "sideboard", label: "Sideboard", category: .storage),
        Term(name: "storage", label: "Storage", category: .storage),
        Term(name: "refrigerator", label: "Fridge", category: .refrigerator),
        Term(name: "sofa", label: "Sofa", category: .sofa),
        Term(name: "bed", label: "Bed", category: .bed),
        Term(name: "table", label: "Table", category: .table),
        Term(name: "chair", label: "Chair", category: .chair),
        Term(name: "television", label: "TV", category: .television),
        Term(name: "stove", label: "Stove", category: .stove),
        Term(name: "oven", label: "Oven", category: .oven),
        Term(name: "dishwasher", label: "Dishwasher", category: .dishwasher),
        Term(name: "sink", label: "Sink", category: .sink),
        Term(name: "bathtub", label: "Bath", category: .bathtub),
        Term(name: "toilet", label: "Toilet", category: .toilet),
        Term(name: "fireplace", label: "Fireplace", category: .fireplace),
        Term(name: "washer dryer", label: "Washer", category: .washerDryer),
        Term(name: "stairs", label: "Stairs", category: .stairs),
    ]

    /// What the correction screen offers for a thing the scan called a fridge:
    /// the four it is most likely to really be, then the scan's own answer.
    static let commonCorrections = ["wardrobe", "cabinet", "shelf", "chest of drawers"]

    /// A free-text correction read back into a term. Unknown words are kept as
    /// they were typed rather than discarded — the service is given the user's
    /// own word, and the proxy falls back to a plain box, which is what
    /// RoomPlan would have given it anyway.
    static func term(forCorrection text: String) -> Term {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.lowercased()
        if let match = known.first(where: { $0.name == folded }) { return match }
        // "fridge" and friends, as a person would say them.
        if let match = known.first(where: { synonyms(of: $0.name).contains(folded) }) {
            return match
        }
        return Term(name: folded, label: trimmed.capitalized, category: nil)
    }

    private static func synonyms(of name: String) -> Set<String> {
        switch name {
        case "refrigerator": return ["fridge", "freezer"]
        case "wardrobe": return ["closet", "armoire"]
        case "sofa": return ["couch", "settee"]
        case "chest of drawers": return ["dresser", "drawers"]
        case "television": return ["tv"]
        case "shelf": return ["shelves", "shelving"]
        default: return []
        }
    }
}
