import SwiftUI

/// Ideas for this particular room, as chips under the prompt.
///
/// Fetched once, when asked for. The screen opens often and a network call every
/// time would buy nothing; and if it fails the box is still a box.
struct SuggestionIdeas: View {
    @Binding var text: String
    let room: ScannedRoom

    @Environment(\.roomAccent) private var accent
    @State private var suggestions: [String] = []
    @State private var isSuggesting = false
    @State private var suggestionsFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if suggestions.isEmpty {
                Button {
                    Task { await loadSuggestions() }
                } label: {
                    HStack(spacing: 7) {
                        if isSuggesting {
                            ProgressView().controlSize(.small)
                            Text("Finding ideas…")
                        } else {
                            Image(systemName: "sparkles")
                            Text(suggestionsFailed ? "Try again" : "Suggest ideas")
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Paper.quietInk)
                    .frame(height: 44)
                    .padding(.horizontal, 16)
                    .background(Paper.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSuggesting || room.capturedRoom == nil)

                if suggestionsFailed {
                    Text("No ideas came back this time. Type your own.")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                }
            } else {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { text = suggestion } label: {
                        Text(suggestion)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(text == suggestion ? .white : Paper.quietInk)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(text == suggestion ? accent : Paper.tint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadSuggestions() async {
        guard let captured = room.capturedRoom else { return }
        isSuggesting = true
        suggestionsFailed = false
        defer { isSuggesting = false }

        // Deliberately no alert: a missing suggestion is not an error the user
        // has to deal with, it just means typing the brief instead.
        let fetched = (try? await PlanService().suggestions(for: RoomFacts(room: captured))) ?? []
        suggestions = fetched
        suggestionsFailed = fetched.isEmpty
    }
}
