import PhotosUI
import SwiftData
import SwiftUI

/// Bringing a photograph in from the camera roll.
///
/// `PhotosPicker` is deliberately the whole of it. The picker runs out of
/// process — "so photo library access authorization is not needed", in the
/// framework header's own words — which means the app never asks for the
/// library and never sees a photo the user did not hand over.
///
/// What comes back is turned into the same JPEG and thumbnail a scan photo
/// keeps, at the same size, so from that moment on there is one kind of photo
/// in a room and only one thing that tells them apart: whether it knows where
/// it was taken from.
enum PhotoUpload {

    /// The long edge a room photo is kept at — `PhotoEncoder`'s floor for a scan
    /// photo, and about what an image model works at.
    static let longEdge: CGFloat = 1920
    static let thumbnailEdge: CGFloat = 320

    struct Prepared {
        var jpeg: Data
        var thumbnail: Data?
    }

    /// Decoded through ImageIO, which scales while decoding and applies the EXIF
    /// turn — so a 48 MP photo never sits in memory whole, and what is stored is
    /// already upright, which is what `PhotoPose` assumes of it.
    static func prepare(_ data: Data) async -> Prepared? {
        await Task.detached(priority: .userInitiated) { () -> Prepared? in
            guard let full = LibraryImage.thumbnail(from: data, maxPixelSize: longEdge),
                  let jpeg = full.jpegData(compressionQuality: 0.85) else { return nil }
            let small = LibraryImage.thumbnail(from: data, maxPixelSize: thumbnailEdge)?
                .jpegData(compressionQuality: 0.7)
            return Prepared(jpeg: jpeg, thumbnail: small)
        }.value
    }
}

/// The one way a photo gets into a room, so every screen that offers it offers
/// the same thing: pick, prepare, keep it, and hand it back so that the
/// question of where it belongs can be put straight away rather than saved up.
struct RoomPhotoPicker: ViewModifier {
    let room: ScannedRoom
    @Binding var isPresented: Bool
    let onAdded: (ScanPhoto) -> Void

    @Environment(\.modelContext) private var context
    @State private var picked: PhotosPickerItem?
    @State private var failed = false

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $picked, matching: .images)
            .task(id: picked) { await take() }
            .alert("That photo couldn't be read", isPresented: $failed) {
                Button("OK") {}
            } message: {
                Text("Try another one.")
            }
    }

    private func take() async {
        guard let item = picked else { return }
        // Cleared first: the same photo picked twice must run this again.
        picked = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = await PhotoUpload.prepare(data)
        else { return failed = true }

        let photo = ScanPhoto(uploaded: prepared.jpeg, thumbnailData: prepared.thumbnail)
        context.insert(photo)
        photo.room = room
        try? context.save()
        onAdded(photo)
    }
}

extension View {
    func roomPhotoPicker(room: ScannedRoom, isPresented: Binding<Bool>,
                         onAdded: @escaping (ScanPhoto) -> Void) -> some View {
        modifier(RoomPhotoPicker(room: room, isPresented: isPresented, onAdded: onAdded))
    }
}
