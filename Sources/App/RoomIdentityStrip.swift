import RoomPlan
import SwiftUI

/// The one quiet line on the room screen that says what the room is taken to be.
///
/// The bug was never a wrong guess — it was a wrong guess nobody could see. A
/// guest room full of kitchen ideas never said "kitchen" anywhere, so there was
/// nothing to disagree with.
struct RoomIdentityStrip: View {
    let room: ScannedRoom
    let onChange: () -> Void

    @Environment(\.roomAccent) private var accent

    /// Decoding a `CapturedRoom` is not cheap and this sits in a body that runs
    /// often, so it is read once and again whenever a correction lands.
    @State private var reading: RoomReading?

    private struct Key: Equatable {
        var corrections: Data?
        var captured: Data?
    }

    private var key: Key { Key(corrections: room.correctionsData, captured: room.capturedRoomData) }

    var body: some View {
        Button(action: onChange) {
            HStack(spacing: 13) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Change")
                    .font(.system(size: 16))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .task(id: key) { reading = room.reading }
        .accessibilityLabel("\(title). \(detail)")
    }

    private var title: String {
        guard let kind = reading?.kind else { return "Not sure what this room is" }
        return reading?.isKindCorrected == true ? "A \(kind)" : "Read as a \(kind)"
    }

    private var detail: String {
        guard reading?.kind != nil else {
            return "Say what it is and every idea you are offered will suit it."
        }
        return reading?.isKindCorrected == true
            ? "Your word, not the scan's. Every idea you are offered comes from this."
            : "Worked out from the scan. Every idea you are offered comes from this."
    }
}
