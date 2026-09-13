import SwiftUI

/// "Suggest ideas" and the chips it brings back, shared by both ways of designing a room.
///
/// Fetched once, when asked for. The screen opens often and a network call every
/// time would buy nothing; and if it fails the box is still a box.
struct SuggestionIdeas: View {
    @Binding var text: String
    let room: ScannedRoom

    @State private var suggestions: [String] = []
    @State private var isSuggesting = false
    @State private var suggestionsFailed = false

    var body: some View {
        if suggestions.isEmpty {
            Button {
                Task { await loadSuggestions() }
            } label: {
                if isSuggesting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Finding ideas…")
                    }
                } else {
                    Label(suggestionsFailed ? "Try again" : "Suggest ideas",
                          systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isSuggesting || room.capturedRoom == nil)

            if suggestionsFailed {
                Text("No ideas came back this time. Type your own.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { text = suggestion } label: {
                            Text(suggestion)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3, reservesSpace: true)
                                .frame(width: 180, alignment: .topLeading)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(text == suggestion ? Color.accentColor : Color.secondary)
                    }
                }
                .padding(.horizontal, 1)
            }
            Text("Tap an idea to use it, then edit it however you like.")
                .font(.caption2).foregroundStyle(.secondary)
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
