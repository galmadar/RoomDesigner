import SwiftData
import SwiftUI

/// One room: everything it has to show in a single swipeable run — pictures
/// being made, pictures made, then the photos of the room as it really is —
/// and the one thing worth doing next.
struct RoomDetailView: View {
    @Bindable var room: ScannedRoom

    @ObservedObject private var accents = RoomAccents.shared
    @ObservedObject private var jobs = PictureJobs.shared

    @State private var opened: RoomPicture?
    @State private var openedPhoto: ScanPhoto?
    /// A photo waiting to be told where in the room it belongs.
    @State private var placingPhoto: ScanPhoto?
    @State private var isAddingPhoto = false
    /// The card on show, by id rather than index: cards come and go under it.
    @State private var page = ""
    @State private var isShowingGallery = false
    @State private var isShowingPhotos = false
    @State private var isDesigning = false
    @State private var isWalking = false
    @State private var isSeeingScan = false
    @State private var isShowingHelp = false
    @State private var isCorrectingRoom = false

    private var accent: Color { accents.accent(for: room) }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            if room.capturedRoom == nil {
                unscanned
            } else {
                content
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isShowingGallery = true } label: {
                        Label("All pictures", systemImage: "square.grid.2x2")
                    }
                    .disabled(pictures.isEmpty && roomJobs.isEmpty)
                    Button { isShowingPhotos = true } label: {
                        Label("Photos of the room", systemImage: "camera")
                    }
                    .disabled(room.sortedPhotos.isEmpty)
                    Button { isAddingPhoto = true } label: {
                        Label("Add a photo of the room", systemImage: "photo.badge.plus")
                    }
                    Button { isShowingHelp = true } label: {
                        Label("How this works", systemImage: "questionmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Paper.ink)
                }
            }
        }
        .tint(accent)
        .environment(\.roomAccent, accent)
        .task { await accents.load(room) }
        .task { if RoomSeed.opensIdentity { isCorrectingRoom = true } }
        .task { if RoomSeed.opensScan { isSeeingScan = true } }
        .task { if RoomSeed.opens == "pick" { isAddingPhoto = true } }
        .task { if RoomSeed.opens == "design" { isDesigning = true } }
        .task {
            guard RoomSeed.opens == "place" || RoomSeed.opens == "placeByHand" else { return }
            placingPhoto = room.sortedPhotos.first { !$0.isPlaced }
        }
#if DEBUG
        .task {
            if let index = DemoContents.page, cards.indices.contains(index) { page = cards[index].id }
        }
#endif
        .fullScreenCover(item: $opened) { picture in
            PictureDetailView(picture: picture, onDelete: { delete(picture) })
        }
        .fullScreenCover(item: $openedPhoto) { photo in
            PhotoAlignmentView(photo: photo, room: room)
        }
        // Picking a photo asks where it was taken from straight away — once,
        // while it is still the thing being thought about. Skipping is one tap
        // and is never asked again.
        .roomPhotoPicker(room: room, isPresented: $isAddingPhoto) { placingPhoto = $0 }
        .fullScreenCover(item: $placingPhoto) { photo in
            PhotoPlaceFlow(room: room, photo: photo)
                .environment(\.roomAccent, accent)
        }
        .fullScreenCover(isPresented: $isShowingGallery) {
            PictureGalleryView(room: room)
        }
        .fullScreenCover(isPresented: $isShowingPhotos) {
            ScanPhotosView(room: room)
        }
        .sheet(isPresented: $isShowingHelp) { LearnHelpView() }
        .firstPictureLesson(room: room)
        .fullScreenCover(isPresented: $isDesigning) {
            DesignFlowView(room: room)
        }
        .fullScreenCover(isPresented: $isCorrectingRoom) {
            RoomIdentityFlow(room: room) {
                // Designing keeps the screen that asks for it: this hands back
                // to the room's own Design button rather than spending here.
                isCorrectingRoom = false
                Task { @MainActor in isDesigning = true }
            }
        }
        .fullScreenCover(isPresented: $isWalking) {
            WalkView(room: room)
                .environment(\.roomAccent, accent)
        }
        .navigationDestination(isPresented: $isSeeingScan) {
            ScanView(room: room)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            top
            RoomIdentityStrip(room: room) { isCorrectingRoom = true }
            counts
            Spacer(minLength: 12)
            actions
        }
    }

    private var unscanned: some View {
        ContentUnavailableView {
            Label("Nothing scanned", systemImage: "questionmark")
        } description: {
            Text("This room has no scan, so there is nothing to design from.")
        }
    }

    // MARK: - What the room has to show

    /// Newest first, with the pictures the retired one-shot flow left behind
    /// after them, so an old room still shows what it has.
    private var pictures: [RoomPicture] {
        room.sortedPictures.map { RoomPicture.made($0) }
            + room.conceptImages.enumerated().reversed().map { RoomPicture.concept(index: $0, data: $1) }
    }

    /// Pictures of this room still being made, newest first.
    private var roomJobs: [PhotoDesignRun] { jobs.jobs(for: room) }

    /// Everything the room has, in the order it earned: what is being made,
    /// what has been made, then what the room actually looks like.
    private var cards: [RoomPage] {
        roomJobs.map { RoomPage.making($0) }
            + pictures.map { RoomPage.picture($0) }
            + room.sortedPhotos.map { RoomPage.photo($0) }
    }

    @ViewBuilder private var top: some View {
        if cards.isEmpty {
            emptyHero
        } else {
            PictureCarousel(cards: cards, selection: $page, onOpen: open)
        }
    }

    /// A page opens whatever it already opened from its own screen — except a
    /// photo with no place in the room, where checking it against the scan is
    /// the one thing that cannot be done. That one offers to place it instead.
    private func open(_ card: RoomPage) {
        switch card {
        case .picture(let picture): opened = picture
        case .photo(let photo):
            if photo.isPlaced { openedPhoto = photo } else { placingPhoto = photo }
        case .making: break
        }
    }

    private var emptyHero: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("No pictures yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Paper.ink)
            Text("Design makes one from a photo of this room.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 430)
        .background(Paper.tint)
    }

    private func delete(_ picture: RoomPicture) {
        opened = nil
        switch picture {
        case .made(let made):
            room.pictures = (room.pictures ?? []).filter { $0 !== made }
            RoomPicture.modelContext(of: made)?.delete(made)
        case .concept(let index, _):
            // A fresh array, never a removal in place: SwiftData may not see one.
            var remaining = room.conceptImages
            guard remaining.indices.contains(index) else { return }
            remaining.remove(at: index)
            room.conceptImages = remaining
        }
    }

    // MARK: - What is in the carousel

    /// A caption, not a control. The thumbnail row and its "+1 more" stood here
    /// to reach photos the top of the screen could not show; the carousel shows
    /// them, and the grid is still in the menu, so this says what is there and
    /// no longer hides a second way to it.
    private var counts: some View {
        Text(countsText)
            .font(.system(size: 13))
            .foregroundStyle(Paper.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    private var countsText: String {
        let all = room.sortedPhotos
        let photos = all.count
        let made = pictures.count
        let left = made == 1 ? "1 picture" : "\(made) pictures"
        let right = photos == 1 ? "1 photo of the real room" : "\(photos) photos of the real room"
        let working = roomJobs.filter(\.isWorking).count
        let making = working == 0 ? "" : " · \(working) being made"
        let loose = all.filter { !$0.isPlaced }.count
        let unplaced = loose == 0 ? "" : " · \(loose) with no place yet"
        return "\(left) · \(right)\(unplaced)\(making)"
    }

    // MARK: - The one action

    private var actions: some View {
        VStack(spacing: 10) {
            Button { isDesigning = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold))
                    Text("Design")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            // Layout used to stand here. Everything it did — adding a piece,
            // moving, turning, resizing, removing it, keeping an arrangement —
            // is on the plan inside "See the scan", where you can see what
            // moving it does to the room.
            HStack(spacing: 10) {
                Button("Walk") { isWalking = true }
                    .buttonStyle(QuietButtonStyle())
                Button("See the scan") { isSeeingScan = true }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 28)
    }
}

/// A picture of this room, however it was made.
enum RoomPicture: Identifiable {
    case made(GeneratedPicture)
    /// From the retired one-shot flow, kept so old rooms still show their work.
    case concept(index: Int, data: Data)

    var id: String {
        switch self {
        case .made(let picture): return "made-\(picture.persistentModelID.hashValue)"
        case .concept(let index, _): return "concept-\(index)"
        }
    }

    var prompt: String {
        switch self {
        case .made(let picture): return picture.prompt
        case .concept: return "An earlier design of this room"
        }
    }

    var markers: [Marker] {
        guard case .made(let picture) = self else { return [] }
        return picture.products.compactMap(\.marker)
    }

    var caption: String {
        switch self {
        case .made(let picture):
            let count = picture.products.count
            let products = count == 0 ? "Just the room" : (count == 1 ? "1 product" : "\(count) products")
            return "\(products) · from \(picture.angle.lowercased())"
        case .concept:
            return "From the scan"
        }
    }

    var fullData: Data? {
        switch self {
        case .made(let picture): return picture.imageData
        case .concept(_, let data): return data
        }
    }

    var thumbnailData: Data? {
        switch self {
        case .made(let picture): return picture.thumbnailData ?? picture.imageData
        case .concept(_, let data): return data
        }
    }

    static func modelContext(of picture: GeneratedPicture) -> ModelContext? {
        picture.modelContext
    }
}
