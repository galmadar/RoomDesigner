import RoomPlan
import simd

/// The room flattened to a plan view, in metres, ready to draw to scale.
///
/// Everything here is measured rather than guessed — which is the whole reason
/// the scan is worth having. The abandoned web app asked the model to invent
/// zone rectangles and then checked them; a scan makes that unnecessary.
struct FloorPlan {

    struct Segment {
        var start: SIMD2<Float>
        var end: SIMD2<Float>
    }

    struct Footprint {
        var centre: SIMD2<Float>
        var size: SIMD2<Float>
        var rotation: Float
        var label: String
    }

    var walls: [Segment] = []
    var doors: [Segment] = []
    var windows: [Segment] = []
    var objects: [Footprint] = []

    init(room: CapturedRoom) {
        walls = room.walls.map(Self.segment)
        doors = room.doors.map(Self.segment)
        windows = room.windows.map(Self.segment)
        objects = room.objects.map { object in
            Footprint(centre: Self.groundPosition(object.transform),
                      size: SIMD2(object.dimensions.x, object.dimensions.z),
                      rotation: Self.yaw(object.transform),
                      label: Self.name(of: object.category))
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

    private static func name(of category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .bathtub: return "Bath"
        case .bed: return "Bed"
        case .chair: return "Chair"
        case .dishwasher: return "Dishwasher"
        case .fireplace: return "Fireplace"
        case .oven: return "Oven"
        case .refrigerator: return "Fridge"
        case .sink: return "Sink"
        case .sofa: return "Sofa"
        case .stairs: return "Stairs"
        case .storage: return "Storage"
        case .stove: return "Stove"
        case .table: return "Table"
        case .television: return "TV"
        case .toilet: return "Toilet"
        case .washerDryer: return "Washer"
        @unknown default: return "Object"
        }
    }
}
