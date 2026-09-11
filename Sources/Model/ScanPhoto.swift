import Foundation
import SwiftData
import UIKit

/// A photo taken mid-scan, placed in the room by the pose it was taken from.
///
/// Everything later work needs hangs off this: `uprightImage`, `viewpoint`,
/// `camera` and `planSpot`, and `ScannedRoom.sortedPhotos` to list them. The
/// maths lives in `PhotoViewpoint`.
@Model
final class ScanPhoto {
    var takenAt: Date

    /// JPEG, already turned the way the phone was held.
    @Attribute(.externalStorage) var imageData: Data

    /// A small JPEG, so a strip of photos need not decode the full ones.
    var thumbnailData: Data?

    /// An encoded `PhotoViewpoint`: a value owned by this photo, so one blob.
    var viewpointData: Data

    var room: ScannedRoom?

    init(takenAt: Date, imageData: Data, thumbnailData: Data?, viewpoint: PhotoViewpoint) {
        self.takenAt = takenAt
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.viewpointData = (try? JSONEncoder().encode(viewpoint)) ?? Data()
    }

    var viewpoint: PhotoViewpoint? {
        try? JSONDecoder().decode(PhotoViewpoint.self, from: viewpointData)
    }

    /// Decodes the full JPEG; read `imageData` here and decode elsewhere for
    /// anything on a hot path.
    var uprightImage: UIImage? { UIImage(data: imageData) }

    var thumbnail: UIImage? { thumbnailData.flatMap(UIImage.init(data:)) ?? uprightImage }

    /// The renderer camera that sees what this photo saw.
    var camera: Camera? { viewpoint?.camera() }

    var planSpot: PlanSpot? { viewpoint?.planSpot }
}
