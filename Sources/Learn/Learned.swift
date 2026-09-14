import SwiftUI

/// Which of the first-time lessons this person has already been shown.
///
/// UserDefaults rather than SwiftData: it belongs to the person, not to a room,
/// so deleting every room must not make the app explain itself all over again.
@MainActor
final class Learned: ObservableObject {
    static let shared = Learned()

    /// Only the moments that are shown once. The scan's live coaching and the
    /// verdict after it are not here — those belong to every scan.
    enum Moment: String, CaseIterable {
        case firstLaunch
        case beforeScan
        case designWhere
        case firstPicture

        fileprivate var key: String { "learned.\(rawValue)" }
    }

    @Published private var seen: Set<Moment>

    private init() {
        seen = Set(Moment.allCases.filter { UserDefaults.standard.bool(forKey: $0.key) })
    }

    func hasSeen(_ moment: Moment) -> Bool { seen.contains(moment) }

    func mark(_ moment: Moment) {
        guard !seen.contains(moment) else { return }
        seen.insert(moment)
        UserDefaults.standard.set(true, forKey: moment.key)
    }

    /// "Show the first-time cards again". Dismissing a card has to cost nothing,
    /// which it only does if there is one place that puts them all back.
    func showAllAgain() {
        for moment in Moment.allCases { UserDefaults.standard.removeObject(forKey: moment.key) }
        seen = []
    }
}
