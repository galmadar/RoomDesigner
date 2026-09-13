import Foundation
import simd

/// Furniture you propose, as opposed to furniture RoomPlan found.
///
/// This is what turns the app from a restyler into a redesigner. Conditioning
/// on depth means the generator can only furnish where geometry already exists —
/// an empty wall stays an empty wall however the prompt is worded. Adding
/// proposed pieces to the mesh *before* rendering is the way past that.
struct Proposal: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: Furniture.Kind
    /// Where it stands on the floor, in room coordinates (x, z).
    var position: SIMD2<Float>
    var rotation: Float = 0
    /// Width, height, depth in metres. Starts at the kind's default.
    var size: SIMD3<Float>
    /// The library product this piece stands in for. Optional so layouts saved before products existed still decode.
    var libraryObjectID: UUID?

    init(kind: Furniture.Kind, position: SIMD2<Float>) {
        self.kind = kind
        self.position = position
        self.size = kind.defaultSize
    }
}

enum Furniture {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case sofa, bed, table, chair, desk, wardrobe, shelf, rug, lamp, plant
        var id: String { rawValue }

        var label: String {
            switch self {
            case .sofa: return "Sofa"
            case .bed: return "Bed"
            case .table: return "Table"
            case .chair: return "Chair"
            case .desk: return "Desk"
            case .wardrobe: return "Wardrobe"
            case .shelf: return "Shelf"
            case .rug: return "Rug"
            case .lamp: return "Lamp"
            case .plant: return "Plant"
            }
        }

        var symbol: String {
            switch self {
            case .sofa: return "sofa"
            case .bed: return "bed.double"
            case .table: return "table.furniture"
            case .chair: return "chair"
            case .desk: return "studentdesk"
            case .wardrobe: return "cabinet"
            case .shelf: return "books.vertical"
            case .rug: return "square.dashed"
            case .lamp: return "lamp.floor"
            case .plant: return "leaf"
            }
        }

        /// Width, height, depth in metres — ordinary real sizes.
        var defaultSize: SIMD3<Float> {
            switch self {
            case .sofa:     return SIMD3(2.00, 0.80, 0.90)
            case .bed:      return SIMD3(1.60, 0.55, 2.00)
            case .table:    return SIMD3(1.20, 0.75, 0.80)
            case .chair:    return SIMD3(0.50, 0.90, 0.50)
            case .desk:     return SIMD3(1.20, 0.75, 0.60)
            case .wardrobe: return SIMD3(1.00, 2.00, 0.60)
            case .shelf:    return SIMD3(0.80, 1.80, 0.30)
            case .rug:      return SIMD3(2.00, 0.02, 1.40)
            case .lamp:     return SIMD3(0.35, 1.60, 0.35)
            case .plant:    return SIMD3(0.50, 1.20, 0.50)
            }
        }
    }

    /// A rough solid for the kind, centred on the floor at the origin.
    ///
    /// Procedural rather than modelled on purpose: these only ever become a
    /// depth map, a normal map or a silhouette, so what matters is that the
    /// proportions and surface orientations are right — not that it looks like
    /// a particular sofa. It costs no asset pipeline and no licensing.
    static func mesh(for kind: Kind, size: SIMD3<Float>) -> Mesh {
        var builder = Builder()
        let w = size.x, h = size.y, d = size.z

        switch kind {
        case .sofa:
            builder.box(SIMD3(w, h * 0.50, d), at: SIMD3(0, h * 0.25, 0))
            builder.box(SIMD3(w, h * 0.50, d * 0.22), at: SIMD3(0, h * 0.75, -d * 0.39))
            for side in [-1, 1] as [Float] {
                builder.box(SIMD3(w * 0.10, h * 0.30, d),
                            at: SIMD3(side * w * 0.45, h * 0.65, 0))
            }

        case .bed:
            builder.box(SIMD3(w, h * 0.55, d), at: SIMD3(0, h * 0.275, 0))
            builder.box(SIMD3(w, h * 1.10, d * 0.05), at: SIMD3(0, h * 0.55, -d * 0.475))
            builder.box(SIMD3(w * 0.78, h * 0.16, d * 0.13),
                        at: SIMD3(0, h * 0.63, -d * 0.34))

        case .table, .desk:
            builder.box(SIMD3(w, h * 0.07, d), at: SIMD3(0, h * 0.965, 0))
            legs(&builder, width: w, height: h * 0.93, depth: d, thickness: 0.06)

        case .chair:
            builder.box(SIMD3(w, h * 0.06, d), at: SIMD3(0, h * 0.47, 0))
            builder.box(SIMD3(w, h * 0.46, d * 0.10), at: SIMD3(0, h * 0.73, -d * 0.45))
            legs(&builder, width: w, height: h * 0.44, depth: d, thickness: 0.045)

        case .wardrobe:
            builder.box(SIMD3(w, h, d), at: SIMD3(0, h / 2, 0))

        case .shelf:
            builder.box(SIMD3(w, h, d * 0.10), at: SIMD3(0, h / 2, -d * 0.45))
            for level in 0...3 {
                let y = h * (0.12 + 0.28 * Float(level))
                builder.box(SIMD3(w, h * 0.025, d), at: SIMD3(0, y, 0))
            }
            for side in [-1, 1] as [Float] {
                builder.box(SIMD3(w * 0.04, h, d), at: SIMD3(side * w * 0.48, h / 2, 0))
            }

        case .rug:
            builder.box(SIMD3(w, h, d), at: SIMD3(0, h / 2, 0))

        case .lamp:
            builder.box(SIMD3(w * 0.7, h * 0.03, d * 0.7), at: SIMD3(0, h * 0.015, 0))
            builder.box(SIMD3(0.05, h * 0.75, 0.05), at: SIMD3(0, h * 0.4, 0))
            builder.box(SIMD3(w, h * 0.22, d), at: SIMD3(0, h * 0.88, 0))

        case .plant:
            builder.box(SIMD3(w * 0.6, h * 0.25, d * 0.6), at: SIMD3(0, h * 0.125, 0))
            builder.box(SIMD3(w * 0.85, h * 0.60, d * 0.85), at: SIMD3(0, h * 0.62, 0))
        }

        return builder.mesh
    }

    /// `floorLevel` matters: RoomPlan's origin is wherever the scan started —
    /// roughly phone height — so a room's floor sits a metre or more below zero.
    /// Building a sofa up from y = 0 leaves it hanging in the air.
    static func mesh(for proposal: Proposal, floorLevel: Float) -> Mesh {
        mesh(for: proposal.kind, size: proposal.size)
            .transformed(by: placement(of: proposal, floorLevel: floorLevel))
    }

    /// One plain box at the piece's full size: an image model reads a marker's extent from a box, not from a sofa's arms.
    static func box(for proposal: Proposal, floorLevel: Float) -> Mesh {
        var box = ProxyMeshLibrary.box(proposal.size)
        box.positions = box.positions.map { $0 + SIMD3(0, proposal.size.y / 2, 0) }
        return box.transformed(by: placement(of: proposal, floorLevel: floorLevel))
    }

    private static func placement(of proposal: Proposal, floorLevel: Float) -> simd_float4x4 {
        let c = cos(proposal.rotation), s = sin(proposal.rotation)
        return simd_float4x4(
            SIMD4(c, 0, s, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(-s, 0, c, 0),
            SIMD4(proposal.position.x, floorLevel, proposal.position.y, 1)
        )
    }

    private static func legs(_ builder: inout Builder, width: Float, height: Float,
                             depth: Float, thickness: Float) {
        for x in [-1, 1] as [Float] {
            for z in [-1, 1] as [Float] {
                builder.box(SIMD3(thickness, height, thickness),
                            at: SIMD3(x * (width / 2 - thickness),
                                      height / 2,
                                      z * (depth / 2 - thickness)))
            }
        }
    }

    private struct Builder {
        var mesh = Mesh()

        mutating func box(_ size: SIMD3<Float>, at centre: SIMD3<Float>) {
            var part = ProxyMeshLibrary.box(size)
            part.positions = part.positions.map { $0 + centre }
            mesh.append(part)
        }
    }
}
