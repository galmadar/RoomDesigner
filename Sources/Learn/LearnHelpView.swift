import SwiftUI

/// One of the six short things, for the page that is always there.
struct LearnTopic: Identifiable {
    let id = UUID()
    let title: String
    let blurb: String
    let symbol: String?
    let body: [String]

    /// Scanning is pinned at the top because everything else depends on it.
    static let all: [LearnTopic] = [
        LearnTopic(
            title: "Scanning well",
            blurb: "Walk the walls, slowly, into the corners. Everything else depends on this.",
            symbol: "house",
            body: [
                "Go slowly — about one step a second. Rushing leaves the walls soft.",
                "Point at the walls, not only the furniture. The walls are what hold a picture together.",
                "Look into every corner. Corners are where the walls get joined up.",
                "While you scan, the app says one thing at a time if something is going wrong, and marks a corner it has not managed to join yet. When you finish it tells you what it found and what came out thin, and offers to go again before you have spent any time on the room.",
            ]),
        LearnTopic(
            title: "Where you're standing",
            blurb: "Why a photographed spot beats an angle you pick.",
            symbol: nil,
            body: [
                "While you were scanning, every photo you took remembered exactly where you were standing.",
                "Choose one of those spots and the picture is made from there, so it lines up with the room you already know.",
                "Any angle works too. It just has no photograph to match, so it is less true to life.",
            ]),
        LearnTopic(
            title: "Why your room stays your room",
            blurb: "There is a 3D copy of your room under every picture.",
            symbol: nil,
            body: [
                "Your scan is rebuilt as a solid 3D room, and the picture is drawn on top of it.",
                "The walls, the window and the corner cannot move. Only what you asked for changes.",
                "It also means the picture can only put things where there is room for them — which is why furniture you place on the floor plan goes into the 3D room before the picture is drawn.",
            ]),
        LearnTopic(
            title: "Saying how it should feel",
            blurb: "Short sentences work best. Mention the light.",
            symbol: nil,
            body: [
                "\u{201C}Warm and cosy for winter evenings\u{201D} does more than a list of furniture.",
                "Mention the light and the mood. The shapes are already decided by the scan.",
                "If you have placed something on the floor plan, say what you want it to look like rather than where it goes — where is already known.",
            ]),
        LearnTopic(
            title: "Standing inside the room",
            blurb: "Walk at eye height, and fade between the scan and your photo.",
            symbol: nil,
            body: [
                "Walk moves you through the scanned room at eye height, so you can find a spot by looking rather than by reading a map.",
                "Seeing the scan does the same thing standing still, and can jump to the exact spot any photo was taken from.",
                "Both are drawn from the same 3D room the pictures are made from, so what you see there is what a picture would be built on.",
            ]),
        LearnTopic(
            title: "When a picture drifts",
            blurb: "Thin scans, and angles you never photographed.",
            symbol: nil,
            body: [
                "A wall that was never joined into its corners gives the picture nothing solid to sit against, and things looking that way slide.",
                "An angle you picked yourself has no photograph behind it, so the light and the detail are invented rather than matched.",
                "Both are fixed the same way: scan the room again, slowly, into the corners, and take a photo from the spot you care about.",
            ]),
    ]
}

/// Six short things, opened when they are wanted rather than pushed.
struct LearnHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var learned = Learned.shared
    @State private var opened: LearnTopic?
    @State private var hasRestored = false

    var body: some View {
        NavigationStack {
            ZStack {
                Paper.sheet.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Six short things. Open one when you want it.")
                            .font(.system(size: 13))
                            .foregroundStyle(Paper.secondaryInk)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        VStack(spacing: 10) {
                            ForEach(Array(LearnTopic.all.enumerated()), id: \.element.id) { index, topic in
                                row(topic, pinned: index == 0)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        restore
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                    }
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("How this works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                }
            }
            .sheet(item: $opened) { LearnTopicView(topic: $0) }
        }
    }

    private func row(_ topic: LearnTopic, pinned: Bool) -> some View {
        Button { opened = topic } label: {
            HStack(spacing: 12) {
                if let symbol = topic.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(Paper.fallbackAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.16)
                        .foregroundStyle(Paper.ink)
                        .multilineTextAlignment(.leading)
                    Text(topic.blurb)
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pinned ? Paper.fallbackAccent : Paper.mutedInk)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: pinned ? 76 : 68)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if pinned {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Paper.card)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Paper.fallbackAccent, lineWidth: 2)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Paper.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var restore: some View {
        VStack(spacing: 9) {
            Button {
                learned.showAllAgain()
                hasRestored = true
            } label: {
                Label(hasRestored ? "They will show again" : "Show the first-time cards again",
                      systemImage: hasRestored ? "checkmark" : "arrow.clockwise")
            }
            .buttonStyle(QuietButtonStyle(height: 52))
            .disabled(hasRestored)

            Text("This page is under the gear on Rooms,\nand under the \u{22EF} on any room.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One topic, opened.
private struct LearnTopicView: View {
    let topic: LearnTopic

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Paper.sheet.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(topic.blurb)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Paper.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(topic.body, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 14))
                                .foregroundStyle(Paper.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                }
            }
        }
    }
}
