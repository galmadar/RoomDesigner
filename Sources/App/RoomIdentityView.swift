import RoomPlan
import SwiftUI

/// The guess, said out loud, with the reasoning that makes it arguable.
///
/// "Two tables, a sofa, four chairs and one refrigerator" is what turns a
/// correction into a conversation: the shaky object is called out by name,
/// because that is the thing worth arguing with.
struct RoomIdentityView: View {
    @Bindable var room: ScannedRoom
    @Binding var path: [RoomIdentityRoute]
    @Binding var talk: TalkOutcome?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomAccent) private var accent

    /// Decoded once: a `CapturedRoom` is not cheap to decode and the body runs often.
    @State private var captured: CapturedRoom?
    @State private var sentence = ""
    @State private var isInterpreting = false
    @State private var trouble: String?

    private static let kinds = ["Living room", "Bedroom", "Guest room", "Dining room",
                                "Office", "Kitchen", "Bathroom", "Kids' room"]

    private var reading: RoomReading? { captured.map { room.reading(of: $0) } }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headline
                    found
                    decisive
                    choices
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { sentenceBox }
        }
        .navigationTitle("The room")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(Paper.secondaryInk)
            }
        }
        .task { captured = room.rawCapturedRoom }
        .task {
            // Debug-driven only, and through the real endpoint: a hand-made
            // reply would prove nothing about the contract.
            guard let said = RoomSeed.sentence, talk == nil else { return }
            sentence = said
            await interpret()
        }
    }

    // MARK: - The guess

    @ViewBuilder private var headline: some View {
        let reading = reading
        VStack(alignment: .leading, spacing: 8) {
            Text(title(reading))
                .question()
            Text(reading?.isKindCorrected == true
                 ? "Your word, not the scan's. It is what every design idea you are offered is built from."
                 : "You would never have been told. It is what every design idea you are offered is built from.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func title(_ reading: RoomReading?) -> String {
        guard let kind = reading?.kind else { return "Not sure what\nthis room is." }
        if reading?.isKindCorrected == true { return "A \(kind)." }
        return "Read as a\n\(kind)."
    }

    @ViewBuilder private var found: some View {
        if let reading, !reading.tally.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("The scan found")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                FlowLayout(spacing: 8) {
                    ForEach(reading.tally, id: \.name) { entry in
                        Text("^[\(entry.count) \(entry.name)](inflect: true)")
                            .font(.system(size: 14))
                            .foregroundStyle(Paper.quietInk)
                            .frame(height: 38)
                            .padding(.horizontal, 14)
                            .background(Paper.tint, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// The one object that settled the room type. Tapping it is the better fix:
    /// repairing the input makes the room type come out right on its own.
    @ViewBuilder private var decisive: some View {
        if let reading, let id = reading.guess.decidedBy, let object = reading.object(id),
           !reading.isKindCorrected {
            Button { path.append(.object(id)) } label: {
                HStack(spacing: 13) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 19))
                        .foregroundStyle(accent)
                        .frame(width: 40, height: 40)
                        .background(accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("^[1 \(object.name)](inflect: true)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Paper.ink)
                        Text(reason(for: object, kind: reading.guess.kind))
                            .font(.system(size: 13))
                            .foregroundStyle(Paper.secondaryInk)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Paper.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                .shadow(color: Paper.cardShadow, radius: 1.5, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func reason(for object: RoomReading.Object, kind: String?) -> String {
        let width = String(format: "%.1f m", object.dimensions.x)
        var where_ = ""
        if let captured, let distance = PlanMeasure.nearestWallDistance(
            to: object.groundPosition, in: FloorPlan(room: captured, corrections: room.corrections)) {
            where_ = distance < 0.6 ? " and against a wall" : " and out in the room"
        }
        let named = kind.map { "made it a \($0)" } ?? "decided the room"
        return "This is the one that \(named). It is \(width) wide\(where_)."
    }

    // MARK: - Saying what it is

    private var choices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What is it really?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Paper.ink)
            FlowLayout(spacing: 8) {
                ForEach(Self.kinds, id: \.self) { kind in
                    ChoicePill(title: kind,
                               isOn: reading?.corrections.roomKind?.caseInsensitiveCompare(kind) == .orderedSame) {
                        say(kind.lowercased())
                    }
                }
            }
            Text("A guest room is not something the scan can work out on its own. Say it and it sticks.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    private var sentenceBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let trouble {
                Text(trouble)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SentenceField(placeholder: "Or say it in your own words…",
                          text: $sentence, isWorking: isInterpreting) {
                Task { await interpret() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Paper.sheet)
    }

    // MARK: -

    private func say(_ kind: String) {
        room.setRoomKind(kind, guessed: reading?.guess.kind)
        RoomIdeas.shared.roomKindChanged(room)
        path.append(.ideas)
    }

    /// Understanding is the server's job. When it is not there, the pills above
    /// still work — which is why this fails quietly rather than blocking.
    private func interpret() async {
        guard let captured else { return }
        let said = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return }
        isInterpreting = true
        trouble = nil
        defer { isInterpreting = false }

        let reading = room.reading(of: captured)
        let facts = RoomFacts(reading: reading, of: captured)
        do {
            let reply = try await PlanService().interpret(
                sentence: said,
                room: RoomInterpretation.Request.Room(reading: reading, facts: facts))
            sentence = ""
            // Setting it is what pushes it, so the screen can never arrive
            // before the reply it is there to show.
            talk = TalkOutcome(sentence: said, reply: reply)
        } catch {
            trouble = (error as? LocalizedError)?.errorDescription
                ?? "That could not be read just now. Tapping still works."
        }
    }
}
