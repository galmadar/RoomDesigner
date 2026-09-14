import ARKit
import Foundation
import RoomPlan
import SwiftData

/// A room the user has scanned. Everything lives on the device; the server is
/// only ever asked to generate, never to remember.
@Model
final class ScannedRoom {
    var name: String
    var createdAt: Date

    /// An archived `CapturedRoom`. Stored rather than the USDZ export because
    /// the parametric form is what the renderer builds geometry from, and it is
    /// far smaller than a mesh.
    var capturedRoomData: Data?

    /// Generated concept images, newest last.
    @Attribute(.externalStorage) var conceptImages: [Data]

    /// The brief the images were generated from, so a regenerate can reuse it.
    var brief: String?

    /// Furniture the user has proposed, encoded rather than related: it is a
    /// small value type owned entirely by this room, and a single blob avoids
    /// the observation traps of a stored array.
    var proposalsData: Data?

    /// Arrangements saved deliberately, so a layout worth keeping survives the
    /// experimenting that comes after it.
    var arrangementsData: Data?

    /// Photos taken while scanning. Rooms scanned before photos existed have none.
    @Relationship(deleteRule: .cascade, inverse: \ScanPhoto.room)
    var photos: [ScanPhoto]? = []

    /// Pictures made by "Design with photos". Separate from `conceptImages`,
    /// which the one-image Flux flow keeps using as it always has.
    @Relationship(deleteRule: .cascade, inverse: \GeneratedPicture.room)
    var pictures: [GeneratedPicture]? = []

    /// The last live room RoomPlan reported before processing, in the AR
    /// session's own frame — kept to check photo poses against the final room.
    var liveRoomData: Data?

    /// An archived `ARWorldMap` from the session this room was scanned in.
    ///
    /// It is what lets a later session be stood back in the same coordinates,
    /// which is the only way an uploaded photo can be given a measured position
    /// instead of a judged one. A map can only be taken while scanning, so a
    /// room scanned before this was kept has none and never will — see
    /// ``RoomWorldMap``.
    @Attribute(.externalStorage) var worldMapData: Data?

    /// What the user has said the scan got wrong. Encoded rather than related,
    /// for the same reason as proposals: a small value owned by this room, and
    /// one blob sidesteps the observation traps of a stored collection.
    var correctionsData: Data?

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.conceptImages = []
    }

    var proposals: [Proposal] {
        get {
            guard let proposalsData else { return [] }
            return (try? JSONDecoder().decode([Proposal].self, from: proposalsData)) ?? []
        }
        set { proposalsData = try? JSONEncoder().encode(newValue) }
    }

    var arrangements: [Arrangement] {
        get {
            guard let arrangementsData else { return [] }
            return (try? JSONDecoder().decode([Arrangement].self, from: arrangementsData)) ?? []
        }
        set { arrangementsData = try? JSONEncoder().encode(newValue) }
    }

    /// The scan exactly as RoomPlan produced it, corrections and all ignored.
    /// Only the screens that let the user argue with the scan want this.
    var rawCapturedRoom: CapturedRoom? {
        guard let capturedRoomData else { return nil }
        return try? JSONDecoder().decode(CapturedRoom.self, from: capturedRoomData)
    }

    /// The scan as the user has corrected it.
    ///
    /// Deliberately the default: the mesh, the plan, the walk and the facts all
    /// read this, so a correction reaches every one of them without each having
    /// to remember that corrections exist. The one that matters is the mesh —
    /// it is what the picture is drawn around.
    var capturedRoom: CapturedRoom? {
        get {
            guard let capturedRoomData else { return nil }
            let corrections = self.corrections
            guard !corrections.isEmpty else { return rawCapturedRoom }
            return CorrectedScan.room(from: capturedRoomData, corrections: corrections)
                ?? rawCapturedRoom
        }
        set { capturedRoomData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// In the order they were taken; a stored relationship has none of its own.
    var sortedPhotos: [ScanPhoto] {
        (photos ?? []).sorted { $0.takenAt < $1.takenAt }
    }

    /// Photos that know where they were taken from — the only ones a spot, a
    /// cross-fade or a reference image may ever be taken from.
    var placedPhotos: [ScanPhoto] { sortedPhotos.filter(\.isPlaced) }

    /// Whether an uploaded photo can be placed by standing in the room again.
    /// False for every room scanned before the world map was kept, and nothing
    /// done later can make it true.
    var canRelocalise: Bool { worldMapData != nil }

    var sortedPictures: [GeneratedPicture] {
        (pictures ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var liveRoom: CapturedRoom? {
        liveRoomData.flatMap { try? JSONDecoder().decode(CapturedRoom.self, from: $0) }
    }

    var corrections: RoomCorrections {
        get {
            guard let correctionsData else { return .none }
            return (try? JSONDecoder().decode(RoomCorrections.self, from: correctionsData))
                ?? .none
        }
        set { correctionsData = try? JSONEncoder().encode(newValue) }
    }

    /// Says what the room is. Records what it was, so the change can be undone
    /// and so pictures made before it can be told apart from ones made after.
    ///
    /// Always assigns the whole value back: SwiftData does not reliably observe
    /// an in-place mutation of a stored collection.
    func setRoomKind(_ kind: String?, guessed: String?) {
        var updated = corrections
        guard updated.roomKind != kind else { return }
        updated.previousRoomKind = updated.roomKind ?? guessed
        updated.roomKind = kind
        updated.roomKindSetAt = .now
        corrections = updated
    }

    /// Puts the room type back to what it was before the last change.
    func undoRoomKind() {
        var updated = corrections
        updated.roomKind = updated.previousRoomKind
        updated.previousRoomKind = nil
        updated.roomKindSetAt = nil
        corrections = updated
    }

    func correctObject(_ id: UUID,
                       _ change: (inout RoomCorrections.ObjectCorrection) -> Void) {
        var updated = corrections
        var one = updated[id]
        change(&one)
        updated[id] = one
        corrections = updated
    }

    /// What the scan says next to what the user says, for the screens that show
    /// both. Must be handed the *raw* scan: the corrected one already has these
    /// changes in it, and applying a centre shift twice would move the box
    /// twice.
    func reading(of raw: CapturedRoom) -> RoomReading {
        RoomReading(room: raw, corrections: corrections)
    }

    var reading: RoomReading? { rawCapturedRoom.map(reading(of:)) }
}
