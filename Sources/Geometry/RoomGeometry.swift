import RoomPlan
import simd

/// Builds a renderable mesh straight from `CapturedRoom`'s parametric structs.
///
/// Deliberately not via the USDZ export: the parametric form is already in
/// memory, and going through a file would mean writing it, reading it back and
/// depending on a loader — for geometry we can assemble in a few hundred lines.
enum RoomGeometry {

    /// For the picture sent with "Design with photos": marked pieces become solid boxes in
    /// their colour, and every other proposal goes the same neutral grey as scanned furniture.
    struct Markers {
        var colours: [Proposal.ID: SIMD3<Float>]
        /// Unit vector from the scene towards the camera.
        var towardsCamera: SIMD3<Float>
    }

    /// `corrections` reaches the scanned objects and nothing else: walls,
    /// floors, the built ceiling and proposed furniture are untouched by it, so
    /// a room with no corrections builds the identical mesh it always did.
    static func build(from room: CapturedRoom,
                      corrections: RoomCorrections = .none,
                      proposals: [Proposal] = [],
                      markers: Markers? = nil,
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
            mesh.append(surface(wall, apertures: aperturesByParent[wall.identifier] ?? [],
                                colour: Palette.wall))
        }
        for floor in room.floors {
            mesh.append(surface(floor, apertures: [], colour: Palette.floor))
        }
        mesh.append(ceiling(of: room))
        // Corrected objects, not scanned ones: this is the point at which
        // "that fridge is a wardrobe, and it is wider than that" stops being a
        // label and becomes the geometry the picture is drawn around. An object
        // struck out as never having been there is simply absent here.
        for object in RoomReading(room: room, corrections: corrections).objects {
            var solid = proxies.mesh(for: object.scanned,
                                     category: object.category,
                                     dimensions: object.dimensions,
                                     transform: object.transform)
            solid.tint(Palette.scanned)
            mesh.append(solid)
        }
        // Proposed pieces are ordinary geometry by the time the renderer sees
        // them — the generator cannot tell scanned from imagined, which is
        // exactly the point.
        let floorLevel = room.floors.first.map { $0.transform.columns.3.y }
            ?? (mesh.isEmpty ? 0 : mesh.bounds.min.y)
        for proposal in proposals {
            if let markers, let colour = markers.colours[proposal.id] {
                var box = Furniture.box(for: proposal, floorLevel: floorLevel)
                box.tint(colour)
                lean(&box, towards: markers.towardsCamera)
                mesh.append(box)
                continue
            }
            var piece = Furniture.mesh(for: proposal, floorLevel: floorLevel)
            // Green would read as a marker colour to the model, so unmarked pieces go neutral.
            piece.tint(markers == nil ? Palette.proposed : Palette.scanned)
            mesh.append(piece)
        }
        return mesh
    }

    /// The headlight shades a turned-away face down to 45%, which makes yellow read as olive.
    /// Leaning normals at the camera keeps the colour nameable and still leaves the edges visible.
    private static func lean(_ mesh: inout Mesh, towards camera: SIMD3<Float>, edges: Float = 0.8) {
        mesh.normals = mesh.normals.map { simd_normalize(camera + edges * $0) }
    }

    // MARK: -

    /// RoomPlan reports no ceiling at all, which leaves a hole above every
    /// wall. That reads badly in the solid view and, more importantly, tells the
    /// generator the room is open to the sky — so one is built from the floor's
    /// own outline, raised to the top of the walls.
    private static func ceiling(of room: CapturedRoom) -> Mesh {
        guard let floor = room.floors.first,
              let top = room.walls.map({ $0.transform.columns.3.y + $0.dimensions.y / 2 }).max()
        else { return Mesh() }

        var transform = floor.transform
        transform.columns.3.y = top

        let outline = polygon(of: floor)
        guard outline.count >= 3 else { return Mesh() }

        var mesh = Mesh()
        mesh.append(polygon: outline,
                    triangles: Triangulation.earClip(outline),
                    transform: transform, colour: Palette.ceiling)
        return mesh
    }

    private static func surface(_ surface: CapturedRoom.Surface,
                                apertures: [CapturedRoom.Surface],
                                colour: SIMD3<Float>) -> Mesh {
        let outline = polygon(of: surface)
        guard outline.count >= 3 else { return Mesh() }

        var mesh = Mesh()

        if apertures.isEmpty {
            // Keeps the true outline, including non-rectangular walls and
            // floors, which is what `polygonCorners` is for.
            mesh.append(polygon: outline,
                        triangles: Triangulation.earClip(outline),
                        transform: surface.transform, colour: colour)
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
                        transform: surface.transform, colour: colour)
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
