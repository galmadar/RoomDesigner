import SwiftData
import SwiftUI

@main
struct RoomDesignerApp: App {
    var body: some Scene {
        WindowGroup {
            RoomListView()
                // A picture in flight cannot survive the app being killed, so it
                // is cleared here rather than left spinning forever.
                .task { PictureJobs.shared.recoverLost() }
                .modifier(RoomSeeding())
        }
        .modelContainer(for: [ScannedRoom.self, LibraryObject.self, GeneratedPicture.self])
    }
}
