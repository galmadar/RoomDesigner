import Foundation
import SwiftData
import UIKit

/// A picture made by "Design with photos", kept in its room with what made it.
@Model
final class GeneratedPicture {
    var createdAt: Date

    /// The JPEG the model returned. One picture per model on purpose: external
    /// storage leaves a `[Data]` inside SQLite, but moves a single `Data` out.
    @Attribute(.externalStorage) var imageData: Data

    /// Small, so the room's grid never decodes full pictures.
    var thumbnailData: Data?

    var prompt: String

    /// A `PhotoDesignModel` raw value.
    var model: String

    /// "4:3" or "3:4", as sent.
    var aspectRatio: String

    /// "Photo 2" or "Free angle".
    var angle: String

    /// A small copy of the room photo that was sent, kept even if the photo is later deleted.
    var sourcePhotoData: Data?

    /// The scan render that went with it, coloured boxes and all.
    @Attribute(.externalStorage) var scanRenderData: Data?

    /// An encoded `[UsedProduct]`: a small value owned by this picture, so one blob.
    var productsData: Data?

    var room: ScannedRoom?

    init(createdAt: Date = .now, imageData: Data, thumbnailData: Data?, prompt: String,
         model: PhotoDesignModel, aspectRatio: String, angle: String,
         sourcePhotoData: Data?, scanRenderData: Data?, products: [UsedProduct]) {
        self.createdAt = createdAt
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.prompt = prompt
        self.model = model.rawValue
        self.aspectRatio = aspectRatio
        self.angle = angle
        self.sourcePhotoData = sourcePhotoData
        self.scanRenderData = scanRenderData
        self.productsData = try? JSONEncoder().encode(products)
    }

    var products: [UsedProduct] {
        productsData.flatMap { try? JSONDecoder().decode([UsedProduct].self, from: $0) } ?? []
    }

    var modelName: String { PhotoDesignModel(rawValue: model)?.name ?? model }

    var thumbnail: UIImage? { thumbnailData.flatMap(UIImage.init(data:)) }
}

/// A product as it went into a picture. Copied, not linked, so the record
/// still reads right after the product leaves the library.
struct UsedProduct: Codable, Hashable {
    var name: String
    var libraryObjectID: UUID?
    /// The box colour, or nil when it was added without placing.
    var marker: Marker?
}

/// The two image editors behind "Design with photos".
enum PhotoDesignModel: String, CaseIterable, Identifiable {
    case nanoBanana = "nano-banana-2"
    case gptImage = "gpt-image-2"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .nanoBanana: return "Nano Banana 2"
        case .gptImage: return "GPT-Image 2"
        }
    }

    /// What the choice is actually about, on the one screen that offers it.
    var shortName: String {
        switch self {
        case .nanoBanana: return "Fast"
        case .gptImage: return "Best"
        }
    }

    var costNote: String {
        switch self {
        case .nanoBanana: return "about 15 seconds,\naround $0.08"
        case .gptImage: return "about two minutes,\naround $0.15"
        }
    }

    var summary: String {
        switch self {
        case .nanoBanana: return "$0.08 a picture. Usually ready in about 15 seconds."
        case .gptImage: return "About $0.15 a picture, and slower: usually about two minutes."
        }
    }

    var waitingNote: String {
        switch self {
        case .nanoBanana: return "Usually about 15 seconds."
        case .gptImage: return "GPT-Image is slow: it usually takes about two minutes. Keep this screen open."
        }
    }
}
