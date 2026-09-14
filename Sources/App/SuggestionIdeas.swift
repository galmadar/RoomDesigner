import SwiftUI

/// Ideas for this particular room, as chips under the prompt.
///
/// The ideas themselves live in ``RoomIdeas`` rather than in this view, because
/// what they are ideas *for* can change on a different screen: correcting the
/// room type throws these away and asks again, and a `@State` here would have
/// gone on offering kitchen ideas for a guest room.
struct SuggestionIdeas: View {
    @Binding var text: String
    let room: ScannedRoom

    @Environment(\.roomAccent) private var accent
    @ObservedObject private var store = RoomIdeas.shared

    private var state: RoomIdeas.State { store.state(for: room) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.ideas.isEmpty {
                Button {
                    Task { await store.load(room, force: state.failed) }
                } label: {
                    HStack(spacing: 7) {
                        if state.isLoading {
                            ProgressView().controlSize(.small)
                            Text("Finding ideas…")
                        } else {
                            Image(systemName: "sparkles")
                            Text(state.failed ? "Try again" : "Suggest ideas")
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Paper.quietInk)
                    .frame(height: 44)
                    .padding(.horizontal, 16)
                    .background(Paper.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(state.isLoading || room.capturedRoom == nil)

                if state.failed {
                    Text("No ideas came back this time. Type your own.")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                }
            } else {
                ForEach(state.ideas, id: \.self) { suggestion in
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
}
