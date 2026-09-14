import Foundation
import SwiftData
import UIKit

/// A photo of the room, placed in it by the pose it was taken from — when it
/// has one.
///
/// A photo taken mid-scan always has one: ARKit measured it as the room was
/// being built. A photo chosen from the camera roll never does, because a
/// photograph carries no record of where the photographer stood, so its
/// `viewpoint` is nil until someone gives it one and may stay nil forever.
///
/// Everything later work needs hangs off this: `uprightImage`, `viewpoint`,
/// `camera` and `planSpot`, and `ScannedRoom.sortedPhotos` to list them. The
/// maths lives in `PhotoViewpoint`, and `PhotoPose` builds one for a photo that
/// arrived without.
///
/// **A photo with no pose must never be offered as the picture's reference
/// image.** It shows some other part of the room from some other spot, and the
/// model would be told it is looking at the view it is drawing. `isPlaced` is
/// the one test for that; `viewpoint != nil` is what it means, so a pose that
/// fails to decode counts as absent rather than as trusted.
@Model
final class ScanPhoto {

    /// How a photo came to be where it is in the room — and so how far its pose
    /// can be trusted.
    enum Placement: String, Codable, CaseIterable {
        /// Taken mid-scan from RoomPlan's own AR session. The pose is measured.
        case scanned
        /// Chosen from the library and stood on the plan by hand, by lining the
        /// render up against the photograph. As true as the eye that judged it.
        case byHand
        /// Chosen from the library, then placed by standing in the room again
        /// with the scan's own world map reloaded, so the pose is ARKit's.
        case relocalised
        /// Chosen from the library and deliberately left without a pose.
        case unplaced
    }

    var takenAt: Date

    /// JPEG, already turned the way the phone was held.
    @Attribute(.externalStorage) var imageData: Data

    /// A small JPEG, so a strip of photos need not decode the full ones.
    var thumbnailData: Data?

    /// An encoded `PhotoViewpoint`: a value owned by this photo, so one blob.
    /// Empty when this photo has no pose at all.
    var viewpointData: Data

    /// A ``Placement`` raw value. Defaulted to `.scanned` because every photo
    /// that existed before uploading did came from a scan, and a migration must
    /// not quietly demote them.
    var placementRaw: String = Placement.scanned.rawValue

    var room: ScannedRoom?

    init(takenAt: Date, imageData: Data, thumbnailData: Data?, viewpoint: PhotoViewpoint) {
        self.takenAt = takenAt
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.viewpointData = (try? JSONEncoder().encode(viewpoint)) ?? Data()
        self.placementRaw = Placement.scanned.rawValue
    }

    convenience init(_ shot: ScanCamera.Shot) {
        self.init(takenAt: shot.takenAt, imageData: shot.jpeg,
                  thumbnailData: shot.thumbnail, viewpoint: shot.viewpoint)
    }

    /// A photo from the camera roll. It starts with no pose, whatever is done
    /// with it next: even the paths that end in one have to ask the user first.
    init(uploaded jpeg: Data, thumbnailData: Data?, takenAt: Date = .now) {
        self.takenAt = takenAt
        self.imageData = jpeg
        self.thumbnailData = thumbnailData
        self.viewpointData = Data()
        self.placementRaw = Placement.unplaced.rawValue
    }

    var placement: Placement {
        get { Placement(rawValue: placementRaw) ?? .scanned }
        set { placementRaw = newValue.rawValue }
    }

    var viewpoint: PhotoViewpoint? {
        guard !viewpointData.isEmpty else { return nil }
        return try? JSONDecoder().decode(PhotoViewpoint.self, from: viewpointData)
    }

    /// Whether this photo knows where it was taken from. The only safe test:
    /// a pose that will not decode is as absent as one that was never set.
    var isPlaced: Bool { viewpoint != nil }

    /// Whether the picture came from the camera roll rather than from the scan.
    var isUploaded: Bool { placement != .scanned }

    /// Gives the photo a pose, or takes one away. Both halves are written
    /// together so ``isPlaced`` and ``placement`` can never disagree.
    func place(_ viewpoint: PhotoViewpoint?, by placement: Placement) {
        viewpointData = viewpoint.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        self.placement = placement
    }

    /// Decodes the full JPEG; read `imageData` here and decode elsewhere for
    /// anything on a hot path.
    var uprightImage: UIImage? { UIImage(data: imageData) }

    var thumbnail: UIImage? { thumbnailData.flatMap(UIImage.init(data:)) ?? uprightImage }

    /// The renderer camera that sees what this photo saw; nil with no pose.
    var camera: Camera? { viewpoint?.camera() }

    var planSpot: PlanSpot? { viewpoint?.planSpot }

    /// What to call it on screen, in one place so every screen says the same.
    var caption: String {
        switch placement {
        case .scanned: return "Taken while scanning"
        case .byHand: return "Uploaded · placed by hand"
        case .relocalised: return "Uploaded · placed in the room"
        case .unplaced: return "Uploaded · no place in the room yet"
        }
    }
}
