import SwiftUI

/// The ideas, asked again the moment the room changed.
///
/// Ideas are cheap text, so they are thrown out and re-fetched immediately.
/// Pictures already made are not redrawn: they cost money and a wait, so they
/// get one dim line and a button, and nothing happens until it is pressed.
struct RoomIdeasView: View {
    @Bindable var room: ScannedRoom
    var onDesign: () -> Void = {}

    @Environment(\.roomAccent) private var accent
    @ObservedObject private var ideas = RoomIdeas.shared

    private var state: RoomIdeas.State { ideas.state(for: room) }

    /// Pictures made before the room type last changed — genuinely made as
    /// something else, rather than merely old.
    private var madeBefore: Int {
        guard let changedAt = room.corrections.roomKindSetAt else { return 0 }
        return room.sortedPictures.filter { $0.createdAt < changedAt }.count
            + room.conceptImages.count
    }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    banner
                    headline
                    list
                    pictures
                }
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .task { await ideas.load(room) }
    }

    @ViewBuilder private var banner: some View {
        if let kind = room.corrections.roomKind {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.capitalizedFirst)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                    Text(room.corrections.previousRoomKind.map { "Was \($0), a moment ago." }
                         ?? "The scan had not worked one out.")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Undo") {
                    room.undoRoomKind()
                    ideas.roomKindChanged(room)
                }
                .font(.system(size: 15))
                .foregroundStyle(accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("New ideas.")
                .question()
            Text(state.isLoading
                 ? "Being asked again now that the room has changed."
                 : "Asked again the moment you changed the room.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    /// Never a spinner over the whole screen: the room is still usable while
    /// its ideas are on their way.
    @ViewBuilder private var list: some View {
        VStack(spacing: 9) {
            if state.isLoading && state.ideas.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Paper.tint)
                        .frame(height: 62)
                }
            } else if state.ideas.isEmpty {
                Text(state.failed
                     ? "No ideas came back this time. Design still works — type the brief yourself."
                     : "No ideas yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Paper.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(state.ideas, id: \.self) { idea in
                    HStack(spacing: 12) {
                        Text(idea)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Paper.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Paper.mutedInk)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .paperCard()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder private var pictures: some View {
        if madeBefore > 0 {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("^[\(madeBefore) picture](inflect: true) made before this change")
                        .font(.system(size: 15))
                        .foregroundStyle(Paper.ink)
                    Text("They were not redrawn — that costs money and a wait. Say the word.")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Again", action: onDesign)
                    .font(.system(size: 14))
                    .foregroundStyle(Paper.quietInk)
                    .frame(height: 38)
                    .padding(.horizontal, 14)
                    .background(Paper.tint,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Paper.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
    }

    private var footer: some View {
        Button(action: onDesign) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold))
                Text("Design")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Paper.sheet)
    }
}
