import SwiftData
import SwiftUI

/// Where a correction can go next.
enum RoomIdentityRoute: Hashable {
    case object(UUID)
    case size(UUID)
    case ideas
}

/// One sentence and what the service made of it, carried between screens.
///
/// Pushed as an item rather than as a route: a route is a value the stack
/// resolves later, which left a window where the screen existed and the reply
/// did not, and the screen came up blank.
final class TalkOutcome: ObservableObject, Identifiable, Hashable {
    let id = UUID()
    let sentence: String
    @Published var reply: RoomInterpretation.Reply
    /// Questions the user has since answered, so they stop being asked.
    @Published var settled: Set<String> = []

    init(sentence: String, reply: RoomInterpretation.Reply) {
        self.sentence = sentence
        self.reply = reply
    }

    static func == (lhs: TalkOutcome, rhs: TalkOutcome) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Correcting what a room is, as one stack of screens.
///
/// It opens on the guess, because the bug was never a wrong guess — it was a
/// wrong guess nobody could see.
struct RoomIdentityFlow: View {
    @Bindable var room: ScannedRoom
    /// Designing is started from the room screen, never from here: it is the
    /// one action that costs money, and it keeps the screen that asks for it.
    var onDesign: () -> Void = {}

    @ObservedObject private var accents = RoomAccents.shared
    @State private var path: [RoomIdentityRoute] = []
    @State private var talk: TalkOutcome?

    private var accent: Color { accents.accent(for: room) }

    var body: some View {
        NavigationStack(path: $path) {
            RoomIdentityView(room: room, path: $path, talk: $talk)
                .navigationDestination(for: RoomIdentityRoute.self) { route in
                    switch route {
                    case .object(let id):
                        RoomObjectView(room: room, objectID: id, path: $path)
                    case .size(let id):
                        RoomSizeView(room: room, objectID: id, path: $path)
                    case .ideas:
                        RoomIdeasView(room: room, onDesign: onDesign)
                    }
                }
                .navigationDestination(item: $talk) { outcome in
                    RoomTalkView(room: room, outcome: outcome,
                                 onDragOnPlan: { id in talk = nil; path = [.size(id)] },
                                 onSeeIdeas: { talk = nil; path = [.ideas] })
                }
        }
        .tint(accent)
        .environment(\.roomAccent, accent)
        .task { await accents.load(room) }
        .task { openSeededRoute() }
    }

    /// Only ever does anything in a debug build driven by the environment.
    private func openSeededRoute() {
        guard let route = RoomSeed.route, path.isEmpty,
              let captured = room.capturedRoom else { return }
        let reading = room.reading(of: captured)
        guard let id = reading.guess.decidedBy ?? reading.objects.first?.id else { return }
        switch route {
        case "object": path = [.object(id)]
        case "size": path = [.size(id)]
        case "ideas": path = [.ideas]
        default: break
        }
    }
}

// MARK: - Pieces the correction screens share

/// A tappable choice. One tap is always enough; typing is never required.
struct ChoicePill: View {
    let title: String
    var isOn = false
    let action: () -> Void

    @Environment(\.roomAccent) private var accent

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Paper.ink : Paper.quietInk)
                .frame(height: 44)
                .padding(.horizontal, 18)
                .background {
                    if isOn {
                        Capsule().fill(Paper.card)
                            .overlay(Capsule().strokeBorder(accent, lineWidth: 2))
                            .shadow(color: Paper.cardShadow, radius: 1.5, x: 0, y: 1)
                    } else {
                        Capsule().fill(Paper.tint)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// A row of pills that wraps, because room types and furniture names are words
/// of very different lengths and a grid would either clip or waste the screen.
struct WrappingPills<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A white card carrying one settled fact, with a tick.
struct SettledRow: View {
    let title: String
    let detail: String

    @Environment(\.roomAccent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Paper.ink)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }
}

/// The one-sentence box. Typing is always there and never required.
struct SentenceField: View {
    let placeholder: String
    @Binding var text: String
    var isWorking = false
    let onSend: () -> Void

    @Environment(\.roomAccent) private var accent

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(Paper.ink)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { if canSend { onSend() } }

            Button(action: onSend) {
                Group {
                    if isWorking {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 42, height: 42)
                .background(accent.opacity(canSend ? 1 : 0.35),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .paperCard(radius: 16)
    }
}
