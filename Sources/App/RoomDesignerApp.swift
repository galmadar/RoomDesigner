import SwiftData
import SwiftUI

@main
struct RoomDesignerApp: App {
    var body: some Scene {
        WindowGroup {
            RoomListView()
        }
        .modelContainer(for: ScannedRoom.self)
    }
}
