import RoomPlan
import simd

/// Builds a renderable mesh straight from `CapturedRoom`'s parametric structs.
///
/// Deliberately not via the USDZ export: the parametric form is already in
/// memory, and going through a file would mean writing it, reading it back and
/// depending on a loader — for geometry we can assemble in a few hundred lines.
enum RoomGeometry {

    static func build(from room: CapturedRoom,
                      proposals: [Proposal] = [],
                      proxies: ProxyMeshLibrary = .boundingBoxes) -> Mesh {
        var mesh = Mesh()

        // Windows, doors and openings are separate surfaces with their own
        // transforms — not holes in the wall. To get a wall with a real aperture
        // they have to be subtracted from their parent.
        let apertures = room.windows + room.doors + room.openings
        var aperturesByParent: [UUID: [CapturedRoom.Surface]] = [:]
        for aperture in apertures {
            guard let parent = aperture.parentIdentifier else { continue }
            aperturesByParent[parent, default: []].append(aperture)
        }

        for wall in room.walls {
            mesh.append(surface(wall, apertures: aperturesByParent[wall.identifier] ?? []))
        }
        for floor in room.floors {
            mesh.append(surface(floor, apertures: []))
        }
        for object in room.objects {
            mesh.append(proxies.mesh(for: object))
        }
        // Proposed pieces are ordinary geometry by the time the renderer sees
        // them — the generator cannot tell scanned from imagined, which is
        // exactly the point.
        for proposal in proposals {
            mesh.append(Furniture.mesh(for: proposal))
        }
        return mesh
    }

    // MARK: -

    private static func surface(_ surface: CapturedRoom.Surface,
                                apertures: [CapturedRoom.Surface]) -> Mesh {
        let outline = polygon(of: surface)
        guard outline.count >= 3 else { return Mesh() }

        var mesh = Mesh()

        if apertures.isEmpty {
            // Keeps the true outline, including non-rectangular walls and
            // floors, which is what `polygonCorners` is for.
            mesh.append(polygon: outline,
                        triangles: Triangulation.earClip(outline),
                        transform: surface.transform)
            return mesh
        }

        // With apertures we work against the outline's bounding rectangle.
        // Exact for rectangular walls, which is nearly all of them; a wall that
        // is both non-rectangular *and* has a window loses its slanted edge.
        let bounds = boundingRect(of: outline)
        let holes = apertures.compactMap { rect(of: $0, inFrameOf: surface) }

        for piece in Triangulation.subtracting(holes, from: bounds) {
            let corners = piece.corners
            mesh.append(polygon: corners,
                        triangles: Triangulation.earClip(corners),
                        transform: surface.transform)
        }
        return mesh
    }

    /// The surface outline in its own plane. `polygonCorners` carries the real
    /// shape; `dimensions` is the rectangular fallback.
    private static func polygon(of surface: CapturedRoom.Surface) -> [SIMD2<Float>] {
        let corners = surface.polygonCorners
        if corners.count >= 3 {
            return corners.map { SIMD2($0.x, $0.y) }
        }
        let half = SIMD2(surface.dimensions.x, surface.dimensions.y) / 2
        return [SIMD2(-half.x, -half.y), SIMD2(half.x, -half.y),
                SIMD2(half.x, half.y), SIMD2(-half.x, half.y)]
    }

    /// An aperture expressed in its parent wall's local coordinates.
    private static func rect(of aperture: CapturedRoom.Surface,
                             inFrameOf parent: CapturedRoom.Surface) -> Triangulation.Rect? {
        let toLocal = parent.transform.inverse * aperture.transform
        let centre = toLocal.columns.3
        guard centre.x.isFinite, centre.y.isFinite else { return nil }

        let half = SIMD2(aperture.dimensions.x, aperture.dimensions.y) / 2
        return Triangulation.Rect(minX: centre.x - half.x, minY: centre.y - half.y,
                                  maxX: centre.x + half.x, maxY: centre.y + half.y)
    }

    private static func boundingRect(of polygon: [SIMD2<Float>]) -> Triangulation.Rect {
        var low = polygon[0], high = polygon[0]
        for point in polygon.dropFirst() {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        return Triangulation.Rect(minX: low.x, minY: low.y, maxX: high.x, maxY: high.y)
    }
}
