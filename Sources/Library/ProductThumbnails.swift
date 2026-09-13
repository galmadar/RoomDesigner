import UIKit

/// Small pictures of library products, decoded once and off the main thread,
/// so a plan redrawn per drag frame never touches a full JPEG.
@MainActor
final class ProductThumbnails: ObservableObject {
    @Published private(set) var images: [UUID: UIImage] = [:]

    func load(_ objects: [LibraryObject]) async {
        let wanted = objects.compactMap { object in
            images[object.id] == nil ? object.mainImageData.map { (object.id, $0) } : nil
        }
        guard !wanted.isEmpty else { return }
        let decoded = await Task.detached(priority: .userInitiated) {
            wanted.compactMap { id, data in
                LibraryImage.thumbnail(from: data, maxPixelSize: 240).map { (id, $0) }
            }
        }.value
        images.merge(decoded) { _, new in new }
    }
}
