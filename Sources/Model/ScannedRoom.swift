import Foundation
import RoomPlan
import SwiftData

/// A room the user has scanned. Everything lives on the device; the server is
/// only ever asked to generate, never to remember.
@Model
final class ScannedRoom {
    var name: String
    var createdAt: Date

    /// An archived `CapturedRoom`. Stored rather than the USDZ export because
    /// the parametric form is what the renderer builds geometry from, and it is
    /// far smaller than a mesh.
    var capturedRoomData: Data?

    /// Generated concept images, newest last.
    @Attribute(.externalStorage) var conceptImages: [Data]

    /// The brief the images were generated from, so a regenerate can reuse it.
    var brief: String?

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.conceptImages = []
    }

    var capturedRoom: CapturedRoom? {
        get {
            guard let capturedRoomData else { return nil }
            return try? JSONDecoder().decode(CapturedRoom.self, from: capturedRoomData)
        }
        set { capturedRoomData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}
