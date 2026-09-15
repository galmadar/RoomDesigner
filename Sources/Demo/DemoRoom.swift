import Foundation
import RoomPlan
import SwiftData

/// The room a phone that cannot scan is given to look around.
///
/// Scanning needs LiDAR, which only Pro iPhones have, and the App Store cannot
/// be told to hide the app from the rest: `UIRequiredDeviceCapabilities` has no
/// value for a depth sensor. So anyone can install this, and on most iPhones
/// there is no way to ever make a room. This is the room they get instead.
///
/// It is not a scan. `DemoRoom.json` is a `CapturedRoom` written by hand — a
/// rectangular living room, 4.4 m by 3.6 m, with a window, a door and five
/// pieces of furniture, every measurement typed rather than measured. Real
/// scans are the layout of somebody's home and never ship.
///
/// Unlike ``RoomSeed`` and ``DemoContents`` beside it, this is compiled into the
/// release build. It is a part of the app, not a way to drive a simulator.
enum DemoRoom {
    static let name = "Demo living room"

    /// Nil only when the fixture is missing from the bundle, which is a build
    /// problem — so it is logged rather than swallowed.
    static func capturedRoom() -> CapturedRoom? {
        guard let url = Bundle.main.url(forResource: "DemoRoom", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            NSLog("DemoRoom: DemoRoom.json is not in the bundle")
            return nil
        }
        do {
            return try JSONDecoder().decode(CapturedRoom.self, from: data)
        } catch {
            NSLog("DemoRoom: the demo room did not decode — %@", "\(error)")
            return nil
        }
    }

    /// Made once and kept, so opening it a second time does not leave two.
    @MainActor
    @discardableResult
    static func install(into context: ModelContext) -> ScannedRoom? {
        let found = try? context.fetch(
            FetchDescriptor<ScannedRoom>(predicate: #Predicate { $0.isDemo }))
        if let existing = found?.first { return existing }

        guard let captured = capturedRoom() else { return nil }
        let room = ScannedRoom(name: name)
        room.isDemo = true
        room.capturedRoom = captured
        context.insert(room)
        // Saved at once: the room is opened in the same breath it is made.
        try? context.save()
        return room
    }
}
