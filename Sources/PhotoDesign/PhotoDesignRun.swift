import RoomPlan
import SwiftData
import UIKit
import simd

/// One "Design with photos" request, from the scan render to a saved picture.
///
/// Nothing here belongs to a screen. The flow builds an order, hands it to
/// ``PictureJobs`` and closes; the run carries on in the room's collection.
@MainActor
final class PhotoDesignRun: ObservableObject, Identifiable {

    enum Stage: Equatable {
        case idle
        /// Drawing the scan that goes up with the request.
        case preparing
        case uploading(done: Int, of: Int)
        case designing(since: Date)
        case downloading
        case finished
        case failed(String)
        /// The app closed while this was in the air; there is nothing left to resume.
        case lost
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
        /// The scan is drawn inside the run, so the tap that starts it returns at once.
        let capturedRoom: CapturedRoom
        let proposals: [Proposal]
        let markerColours: [Proposal.ID: SIMD3<Float>]
        let shot: Shot
        let products: [Product]

        var aspectRatio: String { shot.aspectRatio }
    }

    let id = UUID()
    let startedAt: Date

    /// What the run needs to reach the room again. The name and date come too:
    /// a persistent id means nothing to the launch that has to place a lost run.
    let roomID: PersistentIdentifier?
    let roomName: String
    let roomCreatedAt: Date?
    let prompt: String

    @Published private(set) var stage: Stage
    @Published private(set) var result: GeneratedPicture?

    /// Called whenever the run stops working, however it stopped.
    var onSettled: ((PhotoDesignRun) -> Void)?

    private let order: Order?
    private weak var room: ScannedRoom?
    private let context: ModelContext?
    private var task: Task<Void, Never>?
    private var assertion: UIBackgroundTaskIdentifier = .invalid

    /// The design flow's own run, which never leaves idle: making a picture
    /// hands the order to ``PictureJobs`` instead.
    init() {
        startedAt = .now
        roomID = nil
        roomName = ""
        roomCreatedAt = nil
        prompt = ""
        stage = .idle
        order = nil
        room = nil
        context = nil
    }

    init(order: Order, room: ScannedRoom, context: ModelContext) {
        startedAt = .now
        roomID = room.persistentModelID
        roomName = room.name
        roomCreatedAt = room.createdAt
        prompt = order.prompt
        stage = .idle
        self.order = order
        self.room = room
        self.context = context
    }

    /// A run a previous launch left in flight, rebuilt only so it can be shown
    /// as lost rather than silently disappearing.
    init(lost: PictureJobs.Unfinished) {
        startedAt = lost.startedAt
        roomID = nil
        roomName = lost.roomName
        roomCreatedAt = lost.roomCreatedAt
        prompt = lost.prompt
        stage = .lost
        order = nil
        room = nil
        context = nil
    }

    var isWorking: Bool {
        switch stage {
        case .preparing, .uploading, .designing, .downloading: return true
        default: return false
        }
    }

    var canRetry: Bool { order != nil }

    var failure: String? {
        switch stage {
        case .failed(let message): return message
        case .lost: return "The app closed before this picture was finished. Design it again to try."
        default: return nil
        }
    }

    func reset() { if !isWorking { stage = .idle } }

    // MARK: - Running

    func start() {
        guard !isWorking, let order, let room, let context else { return }
        result = nil
        beginAssertion()
        task = Task { [weak self] in
            await self?.run(order, room: room, context: context)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        endAssertion()
    }

    /// The system reclaiming the assertion is reported, not hidden: a run cut
    /// short in the background reads as failed and offers to go again.
    private func expire() {
        guard isWorking else { return endAssertion() }
        task?.cancel()
        task = nil
        stage = .failed("iOS stopped this while the app was in the background. Try again with the app open.")
        endAssertion()
        onSettled?(self)
    }

    private func beginAssertion() {
        guard assertion == .invalid else { return }
        // UIKit calls the expiry handler on the main thread, which is this actor.
        assertion = UIApplication.shared.beginBackgroundTask(withName: "Make a picture") { [weak self] in
            MainActor.assumeIsolated { self?.expire() }
        }
    }

    private func endAssertion() {
        guard assertion != .invalid else { return }
        UIApplication.shared.endBackgroundTask(assertion)
        assertion = .invalid
    }

    private func run(_ order: Order, room: ScannedRoom, context: ModelContext) async {
        let service = PhotoDesignService()
        do {
            stage = .preparing
            let mesh = PhotoDesignScene.mesh(of: order.capturedRoom, proposals: order.proposals,
                                             colours: order.markerColours, camera: order.shot.camera)
            guard let render = await ShotRenderer.shared.image(of: mesh, shot: order.shot,
                                                               size: PhotoDesignScene.renderSize),
                  let renderPNG = render.pngData()
            else { throw PhotoDesignService.Failure.unreadable }
            try Task.checkCancellation()

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
                group.addTask { (.scan, try await service.upload(renderPNG, contentType: "image/png")) }
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
            try Task.checkCancellation()

            // The room may have been deleted while this was in the air.
            guard !room.isDeleted, room.modelContext != nil else {
                throw PhotoDesignService.Failure.rejected("That room was deleted while the picture was being made.")
            }

            let picture = GeneratedPicture(
                imageData: image, thumbnailData: thumbnail, prompt: order.prompt, model: order.model,
                aspectRatio: order.aspectRatio, angle: order.angle,
                sourcePhotoData: order.photoData == nil ? nil : order.photoThumbnail,
                scanRenderData: renderPNG,
                products: order.products.map {
                    UsedProduct(name: $0.name, libraryObjectID: $0.libraryObjectID, marker: $0.marker)
                })
            context.insert(picture)
            picture.room = room
            try? context.save()
            result = picture
            stage = .finished
        } catch {
            // An expiry has already said what happened; don't paper over it.
            if case .failed = stage {} else {
                stage = .failed(PhotoDesignService.message(for: error))
            }
        }
        task = nil
        endAssertion()
        onSettled?(self)
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
