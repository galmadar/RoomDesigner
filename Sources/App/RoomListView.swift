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

    /// Lets a simulator run open straight to a room:
    ///   xcrun simctl launch <sim> <bundle> --console
    /// with SIMCTL_CHILD_OPEN_ROOM set. Only used for driving the app without a
    /// device attached; absent in normal use.
    private var roomToOpenOnLaunch: String? {
        ProcessInfo.processInfo.environment["OPEN_ROOM"]
    }

    private var showsFirstLaunch: Bool {
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
            .fullScreenCover(isPresented: $isScanning) {
                ScanFlowView { scan in
                    let room = ScannedRoom(name: "Room \(rooms.count + 1)")
                    room.capturedRoom = scan.room
                    room.liveRoomData = scan.liveRoomData
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
            Text("Scan a room and it lands here, in a colour taken from its own photos. Everything you design lives inside it.")
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
            if !RoomCaptureSession.isSupported { UnsupportedDeviceNotice() }
            Button { isScanning = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "cube.transparent").font(.system(size: 18, weight: .semibold))
                    Text("Scan a room")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
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

private struct UnsupportedDeviceNotice: View {
    var body: some View {
        Text("This device has no LiDAR scanner, so rooms can't be scanned on it.")
            .font(.system(size: 13))
            .foregroundStyle(Paper.secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
