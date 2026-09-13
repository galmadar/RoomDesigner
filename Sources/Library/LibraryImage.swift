import ImageIO
import UIKit

/// Turns whatever a shop or the camera roll hands over into what the library keeps.
enum LibraryImage {

    /// Keeps a JPEG comfortably under the server's 4 MB upload cap.
    static let maxLongEdge: CGFloat = 1600

    /// Six, like a shop import: enough angles without filling the phone.
    static let maxPictures = 6

    /// Any decodable image (HEIC, WebP, PNG…) as a JPEG no longer than
    /// ``maxLongEdge``. Flattened onto white because product shots are often
    /// transparent PNGs, and JPEG would turn the transparency black.
    static func jpeg(from data: Data) -> Data? {
        guard let cgImage = downsampled(data, maxPixelSize: maxLongEdge) else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let flattened = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
        return flattened.jpegData(compressionQuality: 0.85)
    }

    static func thumbnail(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        downsampled(data, maxPixelSize: maxPixelSize).map { UIImage(cgImage: $0) }
    }

    static func jpegInBackground(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) { jpeg(from: data) }.value
    }

    static func thumbnails(for images: [Data], maxPixelSize: CGFloat) async -> [UIImage] {
        await Task.detached(priority: .userInitiated) {
            images.compactMap { thumbnail(from: $0, maxPixelSize: maxPixelSize) }
        }.value
    }

    /// Fetches in parallel and keeps the shop's order; a picture that fails is
    /// skipped rather than sinking the rest.
    static func download(_ urls: [URL]) async -> [Data] {
        await withTaskGroup(of: (Int, Data?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 30
                    guard let (bytes, response) = try? await URLSession.shared.data(for: request),
                          ((response as? HTTPURLResponse)?.statusCode ?? 200) < 300
                    else { return (index, nil) }
                    return (index, jpeg(from: bytes))
                }
            }
            var results = [Data?](repeating: nil, count: urls.count)
            for await (index, data) in group { results[index] = data }
            return results.compactMap { $0 }
        }
    }

    /// ImageIO rather than UIImage: it scales while decoding, so a 48 MP photo
    /// never sits in memory at full size, and it applies the EXIF orientation.
    private static func downsampled(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
