import Foundation
import SwiftData
import UIKit

/// Something found in a shop — a sofa, a lamp, a rug, a painting — kept once
/// and shared by every room, since the same lamp might suit any of them.
@Model
final class LibraryObject {
    var id: UUID
    var name: String
    var createdAt: Date

    /// The product page it was imported from; nil when it came from Photos.
    var sourceURL: URL?

    /// JPEGs, long edge at most 1600 px. The first is the main picture — the one
    /// sent to the image model — so reordering is how the main one is chosen.
    @Attribute(.externalStorage) var imagesData: [Data]

    /// A `Furniture.Kind` raw value, or nil for things it has no shape for
    /// (a painting, a mirror). Stored as a string so an unknown kind can't break the store.
    var kind: String?

    init(name: String, imagesData: [Data], sourceURL: URL? = nil,
         kind: String? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.sourceURL = sourceURL
        self.imagesData = imagesData
        self.kind = kind
    }

    var mainImageData: Data? { imagesData.first }

    var mainImage: UIImage? { mainImageData.flatMap(UIImage.init(data:)) }

    var furnitureKind: Furniture.Kind? {
        get { kind.flatMap(Furniture.Kind.init(rawValue:)) }
        set { kind = newValue?.rawValue }
    }
}
