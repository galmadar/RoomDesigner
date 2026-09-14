import ARKit
import SwiftData
import SwiftUI

/// What to do about a photo that has no place in the room.
///
/// A photograph from the library carries no camera position, and that position
/// is the whole of what makes a photo of the room useful to the app: it is how
/// you can be stood in the spot it was taken from, how the render can be
/// crossed against the photograph to see whether the scan is true, and how the
/// right reference image is chosen when a picture is made. So the question is
/// put once, plainly, with the cost of each answer said out loud.
///
/// And put only once. A photo left without a place is not a loose end to be
/// chased: it sits in the room's carousel like any other, marked for what it
/// is, and can be placed whenever — from here, from the photo grid, or from the
/// step that asks where you are standing. Nothing nags.
struct PhotoPlaceFlow: View {
    let room: ScannedRoom
    let photo: ScanPhoto

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.roomAccent) private var accent

    private enum Step: Hashable { case byHand, standInRoom }

    @State private var path: [Step] = []
    @State private var thumbnail: UIImage?

    var body: some View {
        NavigationStack(path: $path) {
            choice
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .byHand:
                        PhotoPlacementView(room: room, photo: photo) { dismiss() }
                    case .standInRoom:
                        PhotoStandInRoomView(room: room, photo: photo) { dismiss() }
                    }
                }
        }
        .tint(accent)
        .task { if RoomSeed.opens == "placeByHand", path.isEmpty { path = [.byHand] } }
    }

    // MARK: - The question

    private var choice: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    preview
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where was this\ntaken from?").question()
                        Text("A photo from your library doesn't know where you were standing. Say where, and it behaves exactly like a photo taken during the scan — you can stand in the spot, cross it against the scan, and design from it.")
                            .font(.system(size: 14))
                            .foregroundStyle(Paper.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                    VStack(spacing: 12) {
                        byHandCard
                        standInRoomCard
                        skipCard
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("The photo you added")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(Paper.secondaryInk)
            }
        }
        .task { await loadThumbnail() }
    }

    private var preview: some View {
        FilledImage(image: thumbnail, symbol: "photo")
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityLabel("The photo you added")
    }

    private func loadThumbnail() async {
        guard thumbnail == nil else { return }
        let data = photo.thumbnailData ?? photo.imageData
        thumbnail = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
    }

    // MARK: - The three answers

    private var byHandCard: some View {
        card(symbol: "hand.point.up.left",
             title: "Put it on the plan yourself",
             detail: "Stand yourself on the floor plan and turn until the scan lines up with the photograph. Takes a minute, and works for any room.",
             enabled: true) {
            path.append(.byHand)
        }
    }

    private var standInRoomCard: some View {
        card(symbol: "location.viewfinder",
             title: "Go and stand where you took it",
             detail: standInRoomDetail,
             enabled: canStandInRoom) {
            path.append(.standInRoom)
        }
    }

    /// The truth about this room in particular, not a general promise. A room
    /// scanned before the app kept a world map cannot be relocalised into, and
    /// saying otherwise would send someone walking home for nothing.
    private var standInRoomDetail: String {
        if !ARWorldTrackingConfiguration.isSupported {
            return "Not on this device — it can't run the tracking this needs."
        }
        if room.worldMapData == nil {
            return "Not for this room. It was scanned before the app started keeping the map it would need to put you back in the room's own coordinates, and there is no way to make one after the fact. Rooms scanned from now on can do this."
        }
        return "The app puts you back in the room's own coordinates and reads the position off the phone, so it is measured rather than judged. You have to be in the room, and it takes a moment to find its bearings."
    }

    private var canStandInRoom: Bool {
        room.worldMapData != nil && ARWorldTrackingConfiguration.isSupported
    }

    /// One tap, and it is over. Nothing is lost that was ever there: the photo
    /// is kept, shown and usable — it simply has no spot.
    private var skipCard: some View {
        Button {
            photo.place(nil, by: .unplaced)
            try? context.save()
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("Skip — just keep the photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Paper.ink)
                Text("It goes in the room with the others and can be the reference for a picture you frame yourself. No standing spot, and no crossing it against the scan. You can place it later.")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Paper.outline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .buttonStyle(.plain)
    }

    private func card(symbol: String, title: String, detail: String, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Paper.mutedInk)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
