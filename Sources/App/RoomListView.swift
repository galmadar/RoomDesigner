import RoomPlan
import SwiftData
import SwiftUI

/// The first screen: every room as a card in its own colour, showing its newest
/// picture, and the one thing to do if there are none yet.
struct RoomListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScannedRoom.createdAt, order: .reverse) private var rooms: [ScannedRoom]

    @State private var isScanning = false
    @State private var isShowingSettings = false
    @State private var isShowingHelp = false
    @State private var path = NavigationPath()

    @ObservedObject private var learned = Learned.shared
    @EnvironmentObject private var notices: PictureNotices

    /// Lets a simulator run open straight to a room:
    ///   xcrun simctl launch <sim> <bundle> --console
    /// with SIMCTL_CHILD_OPEN_ROOM set. Only used for driving the app without a
    /// device attached; absent in normal use.
    private var roomToOpenOnLaunch: String? {
        ProcessInfo.processInfo.environment["OPEN_ROOM"]
    }

    private var showsFirstLaunch: Bool {
        // The card promises a scan and its one button starts one, so a phone
        // that cannot scan never sees it. What it sees first is the list's own
        // notice, which says so instead of offering it.
        guard RoomCaptureSession.isSupported else { return false }
        guard !learned.hasSeen(.firstLaunch), rooms.isEmpty else { return false }
        #if DEBUG
        // One full-screen cover at a time: a stand-in run wants its own screen.
        if LearnStandIn.requested != nil { return false }
        #endif
        return true
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Paper.sheet.ignoresSafeArea()
                if rooms.isEmpty { empty } else { cards }
            }
            .navigationTitle("Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .navigationDestination(for: ScannedRoom.self) { RoomDetailView(room: $0) }
            .navigationDestination(for: LibraryRoute.self) { _ in LibraryView() }
            .navigationDestination(for: GalleryRoute.self) { _ in GalleryView() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { isShowingHelp = true } label: {
                            Label("How this works", systemImage: "questionmark.circle")
                        }
                        Button { isShowingSettings = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "gearshape").foregroundStyle(Paper.ink)
                    }
                    .accessibilityLabel("Settings and how this works")
                }
                // Pictures live inside the room they were made for; this is the
                // only place they are ever seen together.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(GalleryRoute()) } label: {
                        Image(systemName: "photo.stack").foregroundStyle(Paper.ink)
                    }
                    .accessibilityLabel("Gallery")
                }
                // Always shown: the library doesn't depend on having a room yet.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(LibraryRoute()) } label: {
                        Image(systemName: "square.grid.2x2").foregroundStyle(Paper.ink)
                    }
                    .accessibilityLabel("Library")
                }
            }
            .safeAreaInset(edge: .bottom) { scan }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .sheet(isPresented: $isShowingHelp) { LearnHelpView() }
            #if DEBUG
            // The scan screens need a LiDAR device; this is the only way to see
            // them on a simulator. Never compiled into a release build.
            .fullScreenCover(item: .constant(LearnStandIn.requested)) { LearnStandInView(screen: $0) }
            #endif
            // The one lesson that comes before anything is earned: walking a
            // flat for two minutes has to be agreed to before it happens.
            .fullScreenCover(isPresented: .constant(showsFirstLaunch)) {
                LearnFirstView {
                    learned.mark(.firstLaunch)
                    isScanning = true
                }
            }
            .task {
                guard let wanted = roomToOpenOnLaunch,
                      let room = rooms.first(where: { $0.name == wanted }) else { return }
                path.append(room)
            }
            .task { GallerySeed.installIfAsked(into: context) }
            .task {
                // Stands in for the tap on "Open a demo room", which a script
                // has no way to make. It goes through the button's own code, so
                // what is driven is the shipped path and not a copy of it.
                guard RoomSeed.installsDemoRoom else { return }
                openDemoRoom()
            }
            .task {
                guard GallerySeed.opensGallery else { return }
                path.append(GalleryRoute())
            }
            // Checked on appearing as well as on change: a tap that launched the
            // app from cold sets this before there is a list to open anything in.
            // The rooms are watched too, because on that cold launch the intent
            // arrives before the query has any room to match it against, and
            // nothing would ever ask a second time.
            .task { openRoomIfAsked() }
            .onChange(of: notices.opening) { _, _ in openRoomIfAsked() }
            .onChange(of: rooms.count) { _, _ in openRoomIfAsked() }
            .fullScreenCover(isPresented: $isScanning) {
                ScanFlowView { scan in
                    let room = ScannedRoom(name: "Room \(rooms.count + 1)")
                    room.capturedRoom = scan.room
                    room.liveRoomData = scan.liveRoomData
                    // Only the scan can take a map, and only a room that kept
                    // one can ever be stood back in later.
                    room.worldMapData = scan.worldMapData
                    context.insert(room)
                    for shot in scan.shots {
                        let photo = ScanPhoto(shot)
                        context.insert(photo)
                        photo.room = room
                    }
                }
            }
        }
    }

    /// Opens the room a tapped notice was about. Left standing when no room
    /// matches yet, so a query that has not loaded does not lose the intent.
    private func openRoomIfAsked() {
        guard let wanted = notices.opening,
              let room = rooms.first(where: { wanted.matches($0) }) else { return }
        path.append(room)
        notices.opening = nil
    }

    private var hasDemoRoom: Bool { rooms.contains(where: \.isDemo) }

    /// Made on the tap rather than seeded at launch: a room nobody asked for,
    /// sitting in the list of rooms you scanned, would be the same lie the
    /// notice above it is there to avoid.
    private func openDemoRoom() {
        guard let room = DemoRoom.install(into: context) else { return }
        path.append(room)
    }

    private var cards: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(rooms) { room in
                    Button { path.append(room) } label: { RoomCard(room: room) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { context.delete(room) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("No rooms yet")
                .question()
                .multilineTextAlignment(.center)
            Text(RoomCaptureSession.isSupported
                 ? "Scan a room and it lands here, in a colour taken from its own photos. Everything you design lives inside it."
                 : "Rooms come from a scan, and this iPhone cannot make one. The demo room below is here so there is something to look around.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    /// The one filled action on the screen, in the same place whether or not
    /// there are rooms already.
    private var scan: some View {
        VStack(spacing: 10) {
            if RoomCaptureSession.isSupported {
                Button { isScanning = true } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "cube.transparent").font(.system(size: 18, weight: .semibold))
                        Text("Scan a room")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                // "Scan a room" is not offered at all here: it is the one thing
                // this phone cannot do, and a button that only ever leads to an
                // apology is worse than saying so first.
                UnsupportedDeviceNotice()
                Button { openDemoRoom() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "cube.transparent").font(.system(size: 18, weight: .semibold))
                        Text(hasDemoRoom ? "Open the demo room" : "Open a demo room")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Paper.sheet)
    }
}

/// One room: its own colour, its newest picture, and how big it is.
private struct RoomCard: View {
    let room: ScannedRoom

    @ObservedObject private var accents = RoomAccents.shared
    @ObservedObject private var jobs = PictureJobs.shared
    @State private var cover: UIImage?

    private var accent: Color { accents.accent(for: room) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The room's own colour, before anything else on the card.
            accent.frame(height: 5)
            picture
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.36)
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                // So something cooking is visible without opening the room.
                ForEach(jobs.jobs(for: room)) { job in
                    MakingPictureBadge(job: job)
                        .environment(\.roomAccent, accent)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .paperCard()
        .task { await accents.load(room) }
        .task(id: coverData) { await loadCover() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.name). \(summary)")
    }

    @ViewBuilder private var picture: some View {
        if let cover {
            FilledImage(image: cover)
                .frame(height: 168)
                .frame(maxWidth: .infinity)
        } else {
            ZStack {
                Paper.tint
                Image(systemName: room.capturedRoom == nil ? "questionmark" : "sparkles")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(accent.opacity(0.7))
            }
            .frame(height: 168)
            .frame(maxWidth: .infinity)
        }
    }

    /// The newest picture of the room, or failing that a photo of the real one,
    /// so a room scanned but not yet designed still shows itself.
    private var coverData: Data? {
        room.sortedPictures.first.map { $0.thumbnailData ?? $0.imageData }
            ?? room.conceptImages.last
            ?? room.sortedPhotos.first.flatMap { $0.thumbnailData ?? $0.imageData }
    }

    private func loadCover() async {
        guard let data = coverData else { return cover = nil }
        cover = await Task.detached(priority: .userInitiated) {
            LibraryImage.thumbnail(from: data, maxPixelSize: 900)
        }.value
    }

    private var summary: String {
        guard let captured = room.capturedRoom else { return "Not scanned" }
        let area = FloorPlan(room: captured).floorAreaSquareMetres
        return String(format: "%.1f m² · %d objects", area, captured.objects.count)
    }
}

/// What this phone can and cannot do, said before anything is offered.
///
/// It replaces a line that was a dead end. Scanning needs LiDAR and this phone
/// has none; that cannot be worked around and is not worth softening. What can
/// be done is everything a scan feeds, on a room nobody had to scan.
private struct UnsupportedDeviceNotice: View {
    var body: some View {
        VStack(spacing: 5) {
            Text("This iPhone cannot scan a room.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Paper.ink)
            Text("Scanning needs the LiDAR sensor, which only Pro iPhones have. Everything built on a scan works here on a demo room: the floor plan, walking through it at eye height, and the design flow as far as the picture itself.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Paper.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
