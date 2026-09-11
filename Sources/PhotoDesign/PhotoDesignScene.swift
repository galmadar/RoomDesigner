import CoreGraphics
import RoomPlan
import simd

/// A library product standing on the plan, with the colour its box gets in the model's picture.
struct PlacedProduct: Identifiable {
    let proposal: Proposal
    let object: LibraryObject
    /// Nil once the eight colours are used up; that piece is left out of the picture.
    let marker: Marker?

    var id: Proposal.ID { proposal.id }
}

/// What "Design with photos" sends besides the prompt: which angle, which photo,
/// and the scan drawn from there with a coloured box where each product goes.
enum PhotoDesignScene {

    /// The compose endpoint's limit, placed and unplaced together.
    static let maxProducts = Marker.allCases.count

    /// Pixels on the long edge of the scan render, about what the models work at.
    static let renderSize = 1280

    /// In the order they were placed, so a piece keeps its colour while others are
    /// moved or restyled. A product deleted from the library quietly stops counting.
    static func placedProducts(_ proposals: [Proposal], library: [LibraryObject]) -> [PlacedProduct] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let linked = proposals.compactMap { proposal in
            proposal.libraryObjectID.flatMap { byID[$0] }.map { (proposal, $0) }
        }
        return linked.enumerated().map { index, pair in
            PlacedProduct(proposal: pair.0, object: pair.1,
                          marker: index < Marker.allCases.count ? Marker.allCases[index] : nil)
        }
    }

    /// Exactly the photo's camera and aspect, so the render and the photo line up pixel for pixel.
    static func shot(for viewpoint: PhotoViewpoint) -> Shot {
        let (camera, crop) = viewpoint.squareCamera()
        return Shot(camera: camera, crop: crop, aspectRatio: viewpoint.aspect >= 1 ? "4:3" : "3:4")
    }

    /// Always 4:3 landscape: the free camera's square preview already spans the
    /// lens's field of view across, so this is that preview with the top and bottom trimmed.
    static func freeShot(_ camera: Camera) -> Shot {
        Shot(camera: camera, crop: CGRect(x: 0, y: 0.125, width: 1, height: 0.75), aspectRatio: "4:3")
    }

    static let nearbyDistance: Float = 1.0
    static let nearbyTurn: Float = 30 * .pi / 180

    /// A photo taken within a metre of the camera and pointing within 30° of the
    /// same way still shows the walls and light the picture will; beyond that it misleads.
    static func nearestPhoto(to camera: Camera, among photos: [ScanPhoto]) -> ScanPhoto? {
        let forward = simd_normalize(camera.target - camera.eye)
        var best: (photo: ScanPhoto, score: Float)?
        for photo in photos {
            guard let viewpoint = photo.viewpoint else { continue }
            let distance = simd_distance(viewpoint.eye, camera.eye)
            let turn = acos(min(max(simd_dot(simd_normalize(viewpoint.forward), forward), -1), 1))
            guard distance <= nearbyDistance, turn <= nearbyTurn else { continue }
            let score = distance / nearbyDistance + turn / nearbyTurn
            if score < best?.score ?? .infinity { best = (photo, score) }
        }
        return best?.photo
    }

    /// Whether a spot lies on the scanned floor; nil when the scan has no floor. The free
    /// camera is only kept inside the room's bounding box, which a room at an angle overhangs.
    static func isOnFloor(_ point: SIMD2<Float>, of room: CapturedRoom) -> Bool? {
        guard let floor = room.floors.first else { return nil }
        var corners = floor.polygonCorners.map { SIMD2($0.x, $0.y) }
        if corners.count < 3 {
            let half = SIMD2(floor.dimensions.x, floor.dimensions.y) / 2
            corners = [SIMD2(-half.x, -half.y), SIMD2(half.x, -half.y),
                       SIMD2(half.x, half.y), SIMD2(-half.x, half.y)]
        }
        let outline = corners.map { corner -> SIMD2<Float> in
            let world = floor.transform * SIMD4(corner.x, corner.y, 0, 1)
            return SIMD2(world.x, world.z)
        }
        var inside = false
        var previous = outline[outline.count - 1]
        for current in outline {
            if (current.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }

    static func mesh(of room: CapturedRoom, proposals: [Proposal],
                     placed: [PlacedProduct], camera: Camera) -> Mesh {
        let colours = Dictionary(placed.compactMap { product in
            product.marker.map { (product.proposal.id, $0.rgb) }
        }, uniquingKeysWith: { first, _ in first })
        let towards = simd_normalize(camera.eye - camera.target)
        return RoomGeometry.build(from: room, proposals: proposals,
                                  markers: .init(colours: colours, towardsCamera: towards))
    }
}
