import Foundation
import SwiftData

/// Every picture being made, in every room.
///
/// Owned by the app rather than by a screen: the design flow closes the moment
/// a picture is started, and the request carries on here.
@MainActor
final class PictureJobs: ObservableObject {
    static let shared = PictureJobs()

    /// Newest first, so a picture being made sits above the ones already made.
    @Published private(set) var jobs: [PhotoDesignRun] = []

    private init() {}

    func jobs(for room: ScannedRoom) -> [PhotoDesignRun] {
        let id = room.persistentModelID
        return jobs.filter { job in
            if let jobID = job.roomID { return jobID == id }
            // Restored from disk, where only the name and the date survived.
            guard let created = job.roomCreatedAt else { return false }
            return job.roomName == room.name
                && abs(created.timeIntervalSince(room.createdAt)) < 0.001
        }
    }

    func start(_ order: PhotoDesignRun.Order, room: ScannedRoom, context: ModelContext) {
        let job = PhotoDesignRun(order: order, room: room, context: context)
        jobs.insert(job, at: 0)
        remember(job)
        job.onSettled = { [weak self] in self?.settled($0) }
        job.start()
    }

    func retry(_ job: PhotoDesignRun) {
        guard job.canRetry else { return }
        remember(job)
        job.onSettled = { [weak self] in self?.settled($0) }
        job.start()
    }

    func dismiss(_ job: PhotoDesignRun) {
        job.cancel()
        forget(job.id)
        jobs = jobs.filter { $0 !== job }
    }

    /// A finished picture replaces its own placeholder; a failed one stays put
    /// until it is retried or waved away, so a picture never fails out of sight.
    private func settled(_ job: PhotoDesignRun) {
        forget(job.id)
        if case .finished = job.stage { jobs = jobs.filter { $0 !== job } }
    }

#if DEBUG
    /// A picture being made that is never made, so the room screen can be driven
    /// on a simulator. Never started, and never remembered on disk.
    func showStandIn(for room: ScannedRoom, prompt: String) {
        let id = room.persistentModelID
        guard !jobs.contains(where: { $0.roomID == id }) else { return }
        jobs.insert(PhotoDesignRun(standingIn: room, prompt: prompt), at: 0)
    }
#endif

    // MARK: - Surviving a cold launch

    /// What is kept on disk about a run in flight: enough to say which room lost
    /// a picture, never enough to resume one. Plain values only — a
    /// `PersistentIdentifier` does not survive a trip through JSON.
    struct Unfinished: Codable {
        var id: UUID
        var roomName: String
        var roomCreatedAt: Date
        var prompt: String
        var startedAt: Date
    }

    private static let storeKey = "picturesInFlight"

    /// Anything still recorded when the app starts died with the last launch.
    /// It is shown as lost, once, and then forgotten.
    func recoverLost() {
        let unfinished = Self.unfinished()
        UserDefaults.standard.removeObject(forKey: Self.storeKey)
        guard !unfinished.isEmpty else { return }
        jobs = unfinished.map { PhotoDesignRun(lost: $0) } + jobs
    }

    private func remember(_ job: PhotoDesignRun) {
        guard let created = job.roomCreatedAt else { return }
        let record = Unfinished(id: job.id, roomName: job.roomName, roomCreatedAt: created,
                                prompt: job.prompt, startedAt: job.startedAt)
        var all = Self.unfinished().filter { $0.id != job.id }
        all.append(record)
        Self.save(all)
    }

    private func forget(_ id: UUID) {
        Self.save(Self.unfinished().filter { $0.id != id })
    }

    private static func unfinished() -> [Unfinished] {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return [] }
        return (try? JSONDecoder().decode([Unfinished].self, from: data)) ?? []
    }

    private static func save(_ all: [Unfinished]) {
        guard !all.isEmpty else { return UserDefaults.standard.removeObject(forKey: storeKey) }
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: storeKey)
    }
}
