import RoomPlan
import simd

/// The room flattened to a plan view, in metres, ready to draw to scale.
///
/// Everything here is measured rather than guessed — which is the whole reason
/// the scan is worth having. The abandoned web app asked the model to invent
/// zone rectangles and then checked them; a scan makes that unnecessary.
///
/// Measured, but not beyond argument: footprints carry the corrected size and
/// the corrected label, so a closet drawn half its real width can be put right
/// on the plan itself.
struct FloorPlan {

    struct Segment {
        var start: SIMD2<Float>
        var end: SIMD2<Float>
    }

    struct Footprint: Identifiable {
        /// The scanned object's own identifier, which is what a correction is
        /// keyed on — and what makes a footprint selectable.
        var id: UUID
        var centre: SIMD2<Float>
        var size: SIMD2<Float>
        var rotation: Float
        var label: String
        /// As RoomPlan measured it, so the plan can draw what is being changed.
        var scannedSize: SIMD2<Float>
        var isCorrected: Bool
    }

    var walls: [Segment] = []
    var doors: [Segment] = []
    var windows: [Segment] = []
    var objects: [Footprint] = []

    init(room: CapturedRoom, corrections: RoomCorrections = .none) {
        self.init(room: room, reading: RoomReading(room: room, corrections: corrections))
    }

    init(room: CapturedRoom, reading: RoomReading) {
        walls = room.walls.map(Self.segment)
        doors = room.doors.map(Self.segment)
        windows = room.windows.map(Self.segment)
        objects = reading.objects.map { object in
            Footprint(id: object.id,
                      centre: object.groundPosition,
                      size: SIMD2(object.dimensions.x, object.dimensions.z),
                      rotation: object.yaw,
                      label: object.label,
                      scannedSize: SIMD2(object.scannedDimensions.x,
                                         object.scannedDimensions.z),
                      isCorrected: object.isCorrected)
        }
    }

    var bounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
        let points = walls.flatMap { [$0.start, $0.end] }
        guard let first = points.first else { return (.zero, .zero) }
        return points.dropFirst().reduce((first, first)) {
            (simd_min($0.0, $1), simd_max($0.1, $1))
        }
    }

    /// Shoelace over the wall endpoints. Approximate for an L-shaped room whose
    /// walls the scanner ordered oddly, but right for ordinary rectangular ones.
    var floorAreaSquareMetres: Float {
        let extent = bounds.max - bounds.min
        return abs(extent.x * extent.y)
    }

    // MARK: -

    private static func segment(_ surface: CapturedRoom.Surface) -> Segment {
        let centre = groundPosition(surface.transform)
        let axis = surface.transform.columns.0            // the surface's own width axis
        let direction = simd_normalize(SIMD2(axis.x, axis.z))
        let half = direction * (surface.dimensions.x / 2)
        return Segment(start: centre - half, end: centre + half)
    }

    private static func groundPosition(_ transform: simd_float4x4) -> SIMD2<Float> {
        SIMD2(transform.columns.3.x, transform.columns.3.z)
    }

    private static func yaw(_ transform: simd_float4x4) -> Float {
        atan2(transform.columns.0.z, transform.columns.0.x)
    }

    /// The plan's own shortened labels. A correction outranks the category, so
    /// this is the fallback for an object the user has not contradicted —
    /// ``RoomReading`` decides which of the two a footprint gets.
    static func name(of category: CapturedRoom.Object.Category) -> String {
        ObjectVocabulary.term(of: category).label
    }
}
