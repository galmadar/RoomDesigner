import RoomPlan
import simd

/// Stand-in shapes for scanned furniture.
///
/// RoomPlan does not give you the shape of a sofa. Apple's own words: *"RoomPlan
/// approximates the size and shape of objects it observes in a scan by using
/// bounding boxes."* Every one of the sixteen categories arrives as a transform
/// and a cuboid — the category is a label on a box.
///
/// Whether boxes are good enough to condition an image model on is an open
/// question and is deliberately not answered here. What matters is that the
/// lookup exists from the start: swapping boxes for procedural proxies or real
/// meshes is then a registration, not a rewrite.
struct ProxyMeshLibrary {
    /// A builder is handed the detected size in metres and returns a mesh
    /// centred on the origin, ready to be placed by the object's transform.
    typealias Builder = (SIMD3<Float>) -> Mesh

    private var builders: [Key: Builder] = [:]

    struct Key: Hashable {
        let category: CapturedRoom.Object.Category
        /// The object's attributes, flattened. iOS 17 tags objects far more
        /// finely than the sixteen categories — sofas as rectangular or
        /// L-shaped, chairs as dining or stool — so this is what a real proxy
        /// library would key on.
        let variant: String
    }

    /// Everything is a box. The honest starting point.
    static let boundingBoxes = ProxyMeshLibrary()

    static func variant(of object: CapturedRoom.Object) -> String {
        object.attributes.map { String(describing: $0) }.sorted().joined(separator: "+")
    }

    mutating func register(_ category: CapturedRoom.Object.Category,
                           variant: String = "",
                           builder: @escaping Builder) {
        builders[Key(category: category, variant: variant)] = builder
    }

    func mesh(for object: CapturedRoom.Object) -> Mesh {
        let specific = Key(category: object.category, variant: Self.variant(of: object))
        let generic = Key(category: object.category, variant: "")
        let builder = builders[specific] ?? builders[generic] ?? Self.box
        return builder(object.dimensions).transformed(by: object.transform)
    }

    /// A unit cuboid, scaled. What RoomPlan actually knows about the object.
    static func box(_ dimensions: SIMD3<Float>) -> Mesh {
        let half = dimensions / 2
        let corners: [SIMD3<Float>] = [
            SIMD3(-half.x, -half.y, -half.z), SIMD3( half.x, -half.y, -half.z),
            SIMD3( half.x,  half.y, -half.z), SIMD3(-half.x,  half.y, -half.z),
            SIMD3(-half.x, -half.y,  half.z), SIMD3( half.x, -half.y,  half.z),
            SIMD3( half.x,  half.y,  half.z), SIMD3(-half.x,  half.y,  half.z),
        ]
        let faces: [([Int], SIMD3<Float>)] = [
            ([0, 3, 2, 1], SIMD3(0, 0, -1)), ([4, 5, 6, 7], SIMD3(0, 0, 1)),
            ([0, 1, 5, 4], SIMD3(0, -1, 0)), ([3, 7, 6, 2], SIMD3(0, 1, 0)),
            ([0, 4, 7, 3], SIMD3(-1, 0, 0)), ([1, 2, 6, 5], SIMD3(1, 0, 0)),
        ]

        var mesh = Mesh()
        for (indices, normal) in faces {
            let base = UInt32(mesh.positions.count)
            for index in indices {
                mesh.positions.append(corners[index])
                mesh.normals.append(normal)
            }
            mesh.indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        return mesh
    }
}

extension Mesh {
    func transformed(by transform: simd_float4x4) -> Mesh {
        var copy = self
        let rotation = simd_float3x3(transform.columns.0.xyz,
                                     transform.columns.1.xyz,
                                     transform.columns.2.xyz)
        copy.positions = positions.map { (transform * SIMD4<Float>($0, 1)).xyz }
        copy.normals = normals.map { simd_normalize(rotation * $0) }
        return copy
    }
}
