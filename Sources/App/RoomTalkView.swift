import RoomPlan
import SwiftUI

/// What one sentence was understood to mean, split apart and each part reversible.
///
/// One sentence can carry three corrections at once, so the screen shows what it
/// understood rather than just doing it. A vague size never becomes an edit: it
/// becomes a question with answers to tap, or a drag on the plan.
struct RoomTalkView: View {
    @Bindable var room: ScannedRoom
    @ObservedObject var outcome: TalkOutcome
    /// Callbacks rather than the stack's own path: this screen is pushed as an
    /// item, and appending to the path from here would mix the two ways of
    /// driving one stack.
    var onDragOnPlan: (UUID) -> Void
    var onSeeIdeas: () -> Void

    @Environment(\.roomAccent) private var accent

    @State private var captured: CapturedRoom?
    @State private var applied = false
    @State private var follow = ""
    @State private var isInterpreting = false
    @State private var trouble: String?
    @State private var changed: [(title: String, detail: String)] = []

    private var questions: [RoomInterpretation.Question] {
        outcome.reply.questions.filter { !outcome.settled.contains($0.id + $0.field) }
    }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    said
                    settled
                    asks
                    unchanged
                    shrug
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { footer }
        }
        .navigationTitle("The room")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .task {
            captured = room.rawCapturedRoom
            apply()
        }
    }

    // MARK: - What was said

    private var said: some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text("You said")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
            Text(outcome.sentence)
                .font(.system(size: 17))
                .foregroundStyle(Paper.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 17)
                .padding(.vertical, 14)
                .background(Paper.tint,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.leading, 34)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    @ViewBuilder private var settled: some View {
        if !changed.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("Changed")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                ForEach(Array(changed.enumerated()), id: \.offset) { _, row in
                    SettledRow(title: row.title, detail: row.detail)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
        }
    }

    /// The box is what the picture gets drawn around, so a vague size is worth
    /// one tap rather than a guess.
    @ViewBuilder private var asks: some View {
        ForEach(questions) { question in
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(question.ask)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                    Text(hint(for: question))
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    ForEach(question.options, id: \.self) { option in
                        optionRow(option.label) { answer(question, metres: option.value) }
                    }
                    optionRow("Drag it on the plan") {
                        if let id = UUID(uuidString: question.id) {
                            outcome.settled.insert(question.id + question.field)
                            onDragOnPlan(id)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }

    private func hint(for question: RoomInterpretation.Question) -> String {
        guard let captured, let id = UUID(uuidString: question.id),
              let object = room.reading(of: captured).object(id) else {
            return "The box is what the picture gets drawn around, so this one is worth a tap."
        }
        let scanned = String(format: "%.1f m", object.scannedDimensions.x)
        return "The box is what the picture gets drawn around, so this one is worth a tap. The scan has it \(scanned)."
    }

    /// Labels are computed from geometry and so come back in English even when
    /// `ask` is in the user's own language. They wrap rather than truncate: a
    /// mixed-language row is fine, a clipped measurement is not.
    private func optionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Paper.quietInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Paper.mutedInk)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Anything not acted on, said plainly. Silence would read as agreement.
    @ViewBuilder private var unchanged: some View {
        if !outcome.reply.unchanged.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Left alone")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                ForEach(outcome.reply.unchanged, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 14))
                        .foregroundStyle(Paper.quietInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
        }
    }

    /// A sentence the service made nothing of comes back as a perfectly good
    /// answer — empty. Saying so beats a screen that looks like it lost the reply.
    @ViewBuilder private var shrug: some View {
        if changed.isEmpty, questions.isEmpty, outcome.reply.unchanged.isEmpty {
            Text("Nothing in that changed the room. Tapping a name above still works.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 22)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let trouble {
                Text(trouble)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            SentenceField(placeholder: "Anything else about the room…",
                          text: $follow, isWorking: isInterpreting) {
                Task { await again() }
            }
            Button("See the new ideas", action: onSeeIdeas)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Paper.sheet)
    }

    // MARK: - Doing what it said

    private func apply() {
        guard !applied, let captured else { return }
        applied = true
        let before = room.reading(of: captured)
        var rows: [(String, String)] = []

        if let kind = outcome.reply.roomKind, kind != before.kind {
            let was = before.kind.map { "Was \($0)." } ?? "Nothing was set before."
            room.setRoomKind(kind, guessed: before.guess.kind)
            RoomIdeas.shared.roomKindChanged(room)
            rows.append((kind.capitalizedFirst, "\(was) Ideas are being asked again now."))
        }

        for edit in outcome.reply.objectEdits {
            guard let id = UUID(uuidString: edit.id), let object = before.object(id) else { continue }
            room.correctObject(id) { correction in
                if let category = edit.category { correction.category = category }
                if let width = edit.widthMetres { correction.widthMetres = width }
                if let depth = edit.depthMetres { correction.depthMetres = depth }
                if let height = edit.heightMetres { correction.heightMetres = height }
            }
            if let category = edit.category {
                rows.append(("The \(object.name) is a \(category)", place(of: object)))
            }
            if edit.widthMetres != nil || edit.depthMetres != nil || edit.heightMetres != nil {
                let width = edit.widthMetres ?? object.dimensions.x
                rows.append((String(format: "%.2f m wide", width),
                             "The box the picture is drawn around changed with it."))
            }
        }
        changed = rows.map { (title: $0.0, detail: $0.1) }
    }

    private func place(of object: RoomReading.Object) -> String {
        guard let captured else { return "Corrected." }
        let plan = FloorPlan(room: captured, corrections: room.corrections)
        guard let distance = PlanMeasure.nearestWallDistance(to: object.groundPosition, in: plan)
        else { return "Corrected." }
        return distance < 0.6 ? "Against a wall." : "Out in the room."
    }

    private func answer(_ question: RoomInterpretation.Question, metres: Float) {
        guard let id = UUID(uuidString: question.id) else { return }
        room.correctObject(id) { correction in
            switch question.field {
            case "depthMetres": correction.depthMetres = metres
            case "heightMetres": correction.heightMetres = metres
            default: correction.widthMetres = metres
            }
        }
        outcome.settled.insert(question.id + question.field)
        changed.append((title: String(format: "%.2f m %@", metres, sizeWord(question.field)),
                        detail: "The box the picture is drawn around changed with it."))
    }

    private func sizeWord(_ field: String) -> String {
        switch field {
        case "depthMetres": return "deep"
        case "heightMetres": return "tall"
        default: return "wide"
        }
    }

    private func again() async {
        guard let captured else { return }
        let said = follow.trimmingCharacters(in: .whitespacesAndNewlines)
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
            follow = ""
            outcome.reply = reply
            applied = false
            apply()
        } catch {
            trouble = (error as? LocalizedError)?.errorDescription
                ?? "That could not be read just now. Tapping still works."
        }
    }
}
