import UIKit

/// The one place gallery tiles get their pictures from.
///
/// The gallery is the only screen that can hold every image in the app at once,
/// and they are stored as JPEG `Data`. Decoding a full one costs about 6 MB of
/// bitmap whatever its file size, so a hundred tiles decoded the obvious way is
/// hundreds of megabytes and a jettison. Two things stop that: `LibraryImage`
/// scales while decoding through ImageIO, so a full-size bitmap never exists at
/// all, and what comes back is kept here under a cost limit rather than on the
/// tile, so scrolling past two hundred pictures cannot grow without bound.
final class GalleryThumbnails: @unchecked Sendable {
    static let shared = GalleryThumbnails()

    /// Tiles are about 115 pt wide, so 360 px covers a 3x screen with a little
    /// room to spare. At four bytes a pixel that is roughly 500 KB decoded.
    static let tilePixels: CGFloat = 360

    private let cache = NSCache<NSString, UIImage>()
    /// So a fast scroll that passes the same tile twice decodes it once.
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        // Roughly 48 tiles' worth. NSCache also empties itself under pressure.
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 240
    }

    func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func image(for key: String, data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        if let hit = cached(key) { return hit }

        let cache = self.cache
        lock.lock()
        let running = inFlight[key]
        let job = running ?? Task.detached(priority: .userInitiated) {
            guard let image = LibraryImage.thumbnail(from: data, maxPixelSize: maxPixelSize)
            else { return nil }
            cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
            return image
        }
        if running == nil { inFlight[key] = job }
        lock.unlock()

        let image = await job.value
        if running == nil {
            lock.lock()
            inFlight[key] = nil
            lock.unlock()
        }
        return image
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
