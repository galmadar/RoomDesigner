import Foundation
import RoomPlan

/// The scan with the user's corrections baked into it.
///
/// A correction has to reach the mesh, because the mesh is what the
/// conditioning image is rendered from — and the mesh is built from a
/// `CapturedRoom` in half a dozen places, most of which have no idea
/// corrections exist. Threading a parameter through them all would mean every
/// one of those call sites had to remember; the ones that forgot would silently
/// render the uncorrected room.
///
/// So the correction is applied to the scan itself, once, and every consumer
/// gets it for free. `CapturedRoom`'s properties are read-only, but it is
/// `Codable`, so the rewrite goes through its own JSON.
enum CorrectedScan {

    /// Nil when the scan cannot be rewritten, so the caller can fall back to
    /// the scan as it was rather than showing nothing.
    static func room(from data: Data, corrections: RoomCorrections) -> CapturedRoom? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let objects = root["objects"] as? [[String: Any]]
        else { return nil }

        var rewritten: [[String: Any]] = []
        for var object in objects {
            guard let identifier = (object["identifier"] as? String).flatMap(UUID.init(uuidString:))
            else {
                rewritten.append(object)
                continue
            }
            let correction = corrections[identifier]
            // Something the scan found that is not there at all leaves no box.
            if correction.isRemoved { continue }
            guard !correction.isEmpty else {
                rewritten.append(object)
                continue
            }

            if var dimensions = (object["dimensions"] as? [NSNumber])?.map(\.doubleValue),
               dimensions.count == 3 {
                if let width = correction.widthMetres { dimensions[0] = Double(width) }
                if let height = correction.heightMetres { dimensions[1] = Double(height) }
                if let depth = correction.depthMetres { dimensions[2] = Double(depth) }
                object["dimensions"] = dimensions
            }

            // Columns 3 of a column-major 4x4, flattened: the box's centre.
            if let shift = correction.centreShift,
               var transform = (object["transform"] as? [NSNumber])?.map(\.doubleValue),
               transform.count == 16 {
                transform[12] += Double(shift.x)
                transform[14] += Double(shift.y)
                object["transform"] = transform
            }

            // Only a name RoomPlan has a category for can be written back; a
            // wardrobe becomes storage, which is the right proxy for a box of
            // clothes and much better than a refrigerator.
            if let name = correction.category,
               let category = ObjectVocabulary.term(forCorrection: name).category {
                object["category"] = [ObjectVocabulary.jsonKey(of: category): [String: Any]()]
            }

            rewritten.append(object)
        }

        root["objects"] = rewritten
        guard let encoded = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return try? JSONDecoder().decode(CapturedRoom.self, from: encoded)
    }
}
