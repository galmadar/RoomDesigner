import SwiftData
import SwiftUI

@main
struct RoomDesignerApp: App {
    /// The notification delegate has to be in place before launch finishes, or
    /// the tap that started the app is never handed over.
    init() {
        MainActor.assumeIsolated { PictureNotices.shared.begin() }
    }

    var body: some Scene {
        WindowGroup {
            RoomListView()
                // A picture in flight cannot survive the app being killed, so it
                // is cleared here rather than left spinning forever.
                .task { PictureJobs.shared.recoverLost() }
                .modifier(RoomSeeding())
                .modifier(PictureNoticing())
                .environmentObject(PictureNotices.shared)
        }
        .modelContainer(for: [ScannedRoom.self, LibraryObject.self, GeneratedPicture.self])
    }
}
