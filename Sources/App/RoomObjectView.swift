import RoomPlan
import SwiftUI

/// What one scanned thing really is.
///
/// Worth more than correcting the room type directly: it repairs the input, so
/// the room type comes out right on its own and stays right next time.
struct RoomObjectView: View {
    @Bindable var room: ScannedRoom
    let objectID: UUID
    @Binding var path: [RoomIdentityRoute]

    @Environment(\.roomAccent) private var accent

    @State private var captured: CapturedRoom?
    @State private var chosen: String?
    @State private var isRemoving = false

    private static let removeTitle = "Not a thing — remove"

    private var reading: RoomReading? { captured.map { room.reading(of: $0) } }
    private var object: RoomReading.Object? { reading?.object(objectID) }

    /// The scan's own answer, offered last — it might have been right.
    private var scannedName: String? {
        captured?.objects.first { $0.identifier == objectID }
            .map { ObjectVocabulary.term(of: $0.category).name }
    }

    private var options: [String] {
        var names = ObjectVocabulary.commonCorrections
        if let scannedName, !names.contains(scannedName) { names.append(scannedName) }
        return names
    }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    plan
                    question
                    pills
                }
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .navigationTitle("One thing in the scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .task {
            captured = room.rawCapturedRoom
            let correction = room.corrections[objectID]
            isRemoving = correction.isRemoved
            // Nothing is picked for you. Starting on the scan's own answer put
            // the screen that exists to contradict it one tap from agreeing.
            chosen = correction.category
        }
    }

    @ViewBuilder private var plan: some View {
        if let captured {
            VStack(alignment: .leading, spacing: 8) {
                ScannedPlanView(plan: FloorPlan(room: captured, corrections: room.corrections),
                                focus: objectID)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                if let object {
                    Text("Read as a \(object.term.name) · \(String(format: "%.1f m", object.scannedDimensions.x)) wide")
                        .font(.system(size: 12))
                        .foregroundStyle(Paper.mutedInk)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("What is this one?")
                .question()
            Text("Tapping the right name here is what stops the room being read as a \(reading?.guess.kind ?? "kitchen").")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var pills: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { name in
                ChoicePill(title: label(for: name), isOn: !isRemoving && chosen == name) {
                    chosen = name
                    isRemoving = false
                }
            }
            ChoicePill(title: Self.removeTitle, isOn: isRemoving) {
                isRemoving = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func label(for name: String) -> String {
        // Only the first letter: "Chest Of Drawers" is not how anyone writes it.
        name == scannedName ? "\(name.capitalizedFirst) after all" : name.capitalizedFirst
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let object, !isRemoving {
                Text("The scan has it \(String(format: "%.1f m", object.scannedDimensions.x)) wide. You can fix that next.")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: save) {
                if isRemoving {
                    Text("Take it out of the scan")
                } else {
                    Text(chosen.map { "It's a \($0)" } ?? "Pick what it is")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(chosen == nil && !isRemoving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Paper.sheet)
    }

    private func save() {
        let wasKind = reading?.kind
        room.correctObject(objectID) { correction in
            correction.isRemoved = isRemoving
            // The scan's own answer is stored as "no correction", so the object
            // goes back to being whatever a future rescan makes of it.
            correction.category = isRemoving || chosen == scannedName ? nil : chosen
        }
        // Repairing the input can change the room type on its own, which is the
        // whole point of preferring this fix to naming the room outright.
        if let captured, room.reading(of: captured).kind != wasKind {
            RoomIdeas.shared.roomKindChanged(room)
        }
        if isRemoving {
            path.removeAll()
        } else {
            path.append(.size(objectID))
        }
    }
}
