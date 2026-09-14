import SwiftUI

/// The moment the app stops looking like a prompt box with extra steps: their
/// own room in three thumbnails, and one sentence about the 3D copy underneath.
struct LearnFirstPictureView: View {
    let picture: GeneratedPicture

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isComparing = false

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Your first picture")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Paper.ink)
                    .frame(height: 52)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        made
                            .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("\u{201C}\(picture.prompt)\u{201D}")
                                .font(.system(size: 17))
                                .tracking(-0.17)
                                .foregroundStyle(Paper.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(source)
                                .font(.system(size: 13))
                                .foregroundStyle(Paper.secondaryInk)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                        VStack(alignment: .leading, spacing: 11) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Why it still looks like your room")
                                    .font(.system(size: 17, weight: .semibold))
                                    .tracking(-0.17)
                                    .foregroundStyle(Paper.ink)
                                Text("Your scan is rebuilt as a solid 3D room, and the picture is drawn on top of it. The walls, the window and the corner cannot move. Only what you asked for changes.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Paper.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            chain
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                    }
                    .padding(.bottom, 16)
                }

                actions
            }
        }
        .task {
            guard image == nil else { return }
            let data = picture.imageData
            image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
        }
    }

    /// Either the picture on its own, or beside the photo it was made from.
    @ViewBuilder private var made: some View {
        if isComparing, let photo = picture.sourcePhotoData.flatMap(UIImage.init(data:)) {
            HStack(spacing: 9) {
                labelled(photo, "your photo")
                labelled(image, "your picture")
            }
            .frame(height: 320)
        } else {
            FilledImage(image: image)
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func labelled(_ picture: UIImage?, _ caption: String) -> some View {
        VStack(spacing: 6) {
            FilledImage(image: picture)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Paper.secondaryInk)
        }
    }

    private var source: String {
        picture.angle.lowercased().hasPrefix("photo")
            ? "From \(picture.angle.lowercased()) — where you were standing."
            : "From an angle you chose yourself."
    }

    /// Their photo, their scan, their picture — all three are already kept with
    /// the picture, so none of this is an illustration.
    private var chain: some View {
        HStack(spacing: 8) {
            step(picture.sourcePhotoData, "your photo", ringed: false)
            arrow
            step(picture.scanRenderData, "your scan", ringed: false)
            arrow
            step(picture.thumbnailData ?? picture.imageData, "your picture", ringed: true)
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Paper.mutedInk)
            .padding(.bottom, 17)
    }

    private func step(_ data: Data?, _ caption: String, ringed: Bool) -> some View {
        VStack(spacing: 6) {
            PictureThumbnail(data: data, maxPixelSize: 240)
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    if ringed {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Paper.fallbackAccent, lineWidth: 2)
                    }
                }
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Paper.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if picture.sourcePhotoData != nil {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { isComparing.toggle() }
                } label: {
                    Label(isComparing ? "See it on its own" : "See it beside the photo",
                          systemImage: "rectangle.split.2x1")
                }
                .buttonStyle(QuietButtonStyle(height: 52))
            }
            Button {
                Learned.shared.mark(.firstPicture)
                dismiss()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold))
                    Text("Keep it")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 28)
    }
}

extension View {
    /// Shows the first picture a room ever produced, once. Everything it needs
    /// is already stored on the picture, so this can fire on the first launch
    /// after an update as happily as on a picture that has just landed.
    func firstPictureLesson(room: ScannedRoom) -> some View {
        modifier(FirstPictureLesson(room: room))
    }
}

private struct FirstPictureLesson: ViewModifier {
    let room: ScannedRoom

    @ObservedObject private var learned = Learned.shared
    @State private var showing: GeneratedPicture?

    init(room: ScannedRoom) { self.room = room }

    func body(content: Content) -> some View {
        content
            .task(id: room.sortedPictures.first?.persistentModelID) { offer() }
            .fullScreenCover(item: $showing) { LearnFirstPictureView(picture: $0) }
    }

    private func offer() {
        guard !learned.hasSeen(.firstPicture), showing == nil,
              let newest = room.sortedPictures.first else { return }
        showing = newest
    }
}
