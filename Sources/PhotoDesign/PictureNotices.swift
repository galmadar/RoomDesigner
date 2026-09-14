import SwiftUI
import UIKit
import UserNotifications

/// Says a picture arrived, or didn't, when nobody is looking at the app.
///
/// Every call here is a no-op without permission. Refusing costs the app
/// nothing it had before: the cards, the retry and the pictures themselves all
/// work exactly as they did.
@MainActor
final class PictureNotices: ObservableObject {
    static let shared = PictureNotices()

    /// A room a tapped notification asked for, for whoever owns the navigation.
    ///
    /// Named and dated rather than identified: a `PersistentIdentifier` means
    /// nothing to the launch that has to act on it, exactly as for a lost run.
    struct Destination: Equatable {
        let roomName: String
        let roomCreatedAt: Date
        /// The picture that arrived, where one did.
        let pictureCreatedAt: Date?

        func matches(_ room: ScannedRoom) -> Bool {
            room.name == roomName
                && abs(room.createdAt.timeIntervalSince(roomCreatedAt)) < 0.001
        }
    }

    /// Set by a tap, cleared by whoever opens the room.
    @Published var opening: Destination?

    /// The app's own question, asked before iOS is allowed to ask its one.
    @Published var isAsking = false

    private let centre = UNUserNotificationCenter.current()
    private let taps = TapHandler()
    private static let askedKey = "askedAboutPictureNotices"

    private init() {}

    /// Called from the app's initialiser. The delegate has to be in place
    /// before launch finishes, or a tap that started the app is never handed
    /// over.
    func begin() {
        centre.delegate = taps
    }

    // MARK: - Asking

    /// Called the moment a picture is asked for, the first time only.
    ///
    /// A beat later on purpose: the design flow has just closed, and an alert
    /// raised into that dismissal is dropped — this one is offered once.
    func considerAsking() {
        guard !UserDefaults.standard.bool(forKey: Self.askedKey), !isAsking else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard await centre.notificationSettings().authorizationStatus == .notDetermined else {
                // Answered already, in Settings or on an earlier install.
                return UserDefaults.standard.set(true, forKey: Self.askedKey)
            }
            isAsking = true
        }
    }

    /// Yes: iOS gets to ask its own question, which is the one that counts.
    func askSystem() {
        settle()
        Task { _ = try? await centre.requestAuthorization(options: [.alert, .sound]) }
    }

    /// No: never asked again, and nothing changes.
    func declineAsking() { settle() }

    private func settle() {
        isAsking = false
        UserDefaults.standard.set(true, forKey: Self.askedKey)
    }

    // MARK: - Announcing

    /// A run that has stopped working, however it stopped.
    ///
    /// Nothing is said while the app is in front: the card on screen has
    /// already said it, and a banner over the thing it describes is noise.
    func announce(_ job: PhotoDesignRun) {
        guard UIApplication.shared.applicationState != .active else { return }
        switch job.stage {
        case .finished:
            post(title: "Your picture is ready",
                 body: "\(job.roomName) — \(job.prompt)",
                 job: job,
                 thumbnail: job.arrival?.thumbnailData,
                 pictureCreatedAt: job.arrival?.pictureCreatedAt)
        case .failed(let message):
            // The same sentence the card uses, so the app says one thing.
            post(title: "This picture didn't make it",
                 body: "\(job.roomName) — \(message)",
                 job: job, thumbnail: nil, pictureCreatedAt: nil)
        default:
            break
        }
    }

    /// Coming back clears what was said while you were away: the pictures are
    /// on screen now, so the banners behind them are stale.
    func clearDelivered() {
        centre.removeAllDeliveredNotifications()
    }

    private func post(title: String, body: String, job: PhotoDesignRun,
                      thumbnail: Data?, pictureCreatedAt: Date?) {
        guard let created = job.roomCreatedAt else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var info: [String: Any] = ["room": job.roomName,
                                   "roomCreatedAt": created.timeIntervalSince1970]
        if let pictureCreatedAt {
            info["pictureCreatedAt"] = pictureCreatedAt.timeIntervalSince1970
        }
        content.userInfo = info
        if let attachment = Self.attachment(thumbnail, id: job.id) {
            content.attachments = [attachment]
        }

        // No trigger: delivered now, which is when it happened. Filed on this
        // thread rather than from a task — the run has just given up the
        // assertion keeping the app awake, and a task may never get to run.
        let request = UNNotificationRequest(identifier: job.id.uuidString,
                                            content: content, trigger: nil)
        centre.add(request, withCompletionHandler: nil)
    }

    /// The picture itself, written where the system can take it. It moves the
    /// file into its own store, so nothing is left behind to clean up.
    private static func attachment(_ data: Data?, id: UUID) -> UNNotificationAttachment? {
        guard let data else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("picture-notice-\(id.uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: id.uuidString, url: url)
    }
}

/// The notification centre's delegate, which cannot be an actor-isolated type.
private final class TapHandler: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ centre: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let name = info["room"] as? String,
              let created = info["roomCreatedAt"] as? TimeInterval else { return }
        let picture = info["pictureCreatedAt"] as? TimeInterval
        await MainActor.run {
            PictureNotices.shared.opening = .init(
                roomName: name,
                roomCreatedAt: Date(timeIntervalSince1970: created),
                pictureCreatedAt: picture.map(Date.init(timeIntervalSince1970:)))
        }
    }

    /// Nothing is announced over the app itself. One is only ever scheduled
    /// while the app is away, so this catches only the race of coming back in
    /// the same instant one is delivered.
    func userNotificationCenter(_ centre: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [] }
}

/// The app's own question, and the tidy-up that comes with being looked at.
struct PictureNoticing: ViewModifier {
    @ObservedObject private var notices = PictureNotices.shared
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .alert("Tell you when a picture arrives?", isPresented: $notices.isAsking) {
                Button("Tell me") { notices.askSystem() }
                Button("No thanks", role: .cancel) { notices.declineAsking() }
            } message: {
                Text("If you leave the app while a picture is being made, it can send you the picture when it's ready — and say so if it doesn't make it.")
            }
            .onChange(of: phase) { _, now in
                if now == .active { notices.clearDelivered() }
            }
    }
}
