import SwiftData
import UIKit

/// One "Design with photos" request, from uploads to a saved picture.
///
/// Not tied to the screen's lifetime: if the screen goes away mid-run the
/// picture still lands in the room's collection.
@MainActor
final class PhotoDesignRun: ObservableObject {

    enum Stage: Equatable {
        case idle
        case uploading(done: Int, of: Int)
        case designing(since: Date)
        case downloading
        case finished
        case failed(String)
    }

    struct Order {
        struct Product {
            let name: String
            let libraryObjectID: UUID
            let imageData: Data
            let marker: Marker?
        }

        let prompt: String
        let model: PhotoDesignModel
        let photoData: Data?
        let photoThumbnail: Data?
        let angle: String
        let renderPNG: Data
        let aspectRatio: String
        let products: [Product]
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var result: GeneratedPicture?

    var isWorking: Bool {
        switch stage {
        case .uploading, .designing, .downloading: return true
        default: return false
        }
    }

    func reset() { if !isWorking { stage = .idle } }

    func start(_ order: Order, room: ScannedRoom, context: ModelContext) {
        guard !isWorking else { return }
        result = nil
        Task { await run(order, room: room, context: context) }
    }

    private func run(_ order: Order, room: ScannedRoom, context: ModelContext) async {
        let service = PhotoDesignService()
        do {
            let photo = order.photoData.map(Self.fitForUpload)
            // Twin chairs share one picture; upload it once.
            var productImages: [UUID: Data] = [:]
            for product in order.products { productImages[product.libraryObjectID] = Self.fitForUpload(product.imageData) }

            let total = 1 + (photo == nil ? 0 : 1) + productImages.count
            stage = .uploading(done: 0, of: total)

            enum Upload { case photo, scan, product(UUID) }
            var uploaded: (photo: String?, scan: String?, products: [UUID: String]) = (nil, nil, [:])
            try await withThrowingTaskGroup(of: (Upload, String).self) { group in
                if let photo {
                    group.addTask { (.photo, try await service.upload(photo, contentType: "image/jpeg")) }
                }
                group.addTask { (.scan, try await service.upload(order.renderPNG, contentType: "image/png")) }
                for (id, data) in productImages {
                    group.addTask { (.product(id), try await service.upload(data, contentType: "image/jpeg")) }
                }
                var done = 0
                for try await (kind, url) in group {
                    switch kind {
                    case .photo: uploaded.photo = url
                    case .scan: uploaded.scan = url
                    case .product(let id): uploaded.products[id] = url
                    }
                    done += 1
                    stage = .uploading(done: done, of: total)
                }
            }
            guard let scanURL = uploaded.scan else { throw PhotoDesignService.Failure.unreadable }

            stage = .designing(since: .now)
            let request = PhotoDesignService.Request(
                prompt: order.prompt, model: order.model, roomPhotoURL: uploaded.photo,
                scanURL: scanURL,
                objects: order.products.compactMap { product in
                    uploaded.products[product.libraryObjectID].map {
                        .init(name: product.name, imageURL: $0, marker: product.marker)
                    }
                },
                aspectRatio: order.aspectRatio)
            let (url, _) = try await service.compose(request)

            stage = .downloading
            let image = try await service.download(url)
            let thumbnail = await Task.detached(priority: .userInitiated) {
                LibraryImage.thumbnail(from: image, maxPixelSize: 480)?.jpegData(compressionQuality: 0.75)
            }.value
            guard thumbnail != nil else { throw PhotoDesignService.Failure.unreadable }

            let picture = GeneratedPicture(
                imageData: image, thumbnailData: thumbnail, prompt: order.prompt, model: order.model,
                aspectRatio: order.aspectRatio, angle: order.angle,
                sourcePhotoData: order.photoData == nil ? nil : order.photoThumbnail,
                scanRenderData: order.renderPNG,
                products: order.products.map {
                    UsedProduct(name: $0.name, libraryObjectID: $0.libraryObjectID, marker: $0.marker)
                })
            context.insert(picture)
            picture.room = room
            try? context.save()
            result = picture
            stage = .finished
        } catch {
            stage = .failed(PhotoDesignService.message(for: error))
        }
    }

    /// Scan photos and library pictures are well under the cap; this only guards the odd huge one.
    nonisolated private static func fitForUpload(_ jpeg: Data) -> Data {
        guard jpeg.count > PhotoDesignService.maxUploadBytes,
              let smaller = LibraryImage.thumbnail(from: jpeg, maxPixelSize: 1920)?
                .jpegData(compressionQuality: 0.8)
        else { return jpeg }
        return smaller
    }
}
