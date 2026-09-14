import ARKit

/// The scan's own map of the room, kept so a later session can be stood back in
/// the coordinates the room was measured in.
///
/// This is the whole reason a photo that was not taken during the scan can ever
/// have a true position. `ARWorldTrackingConfiguration.initialWorldMap` makes
/// ARKit relocalise against the saved map — "the session will attempt to
/// localize to the provided map with a limited tracking state until
/// localization is successful", in the framework's own words — and from then on
/// every camera pose it reports is in the frame the room was built in. Without
/// one, a fresh session's origin is wherever the phone happened to start, and a
/// pose read from it says nothing about this room.
///
/// A map can only be taken while the scan is happening. A room scanned before
/// this existed has none and there is no way to make one for it after the fact,
/// which is why standing in the room is offered for some rooms and not others.
enum RoomWorldMap {

    /// Secure coding because `ARWorldMap` declares `NSSecureCoding` and nothing
    /// else would decode it back.
    static func archived(_ map: ARWorldMap) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
    }

    /// Costly — a map is megabytes of feature points. Never on the main thread,
    /// and never as a computed property something might read in a draw.
    static func unarchived(_ data: Data) -> ARWorldMap? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }
}
