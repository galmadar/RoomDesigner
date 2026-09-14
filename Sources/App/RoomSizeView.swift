import RoomPlan
import SwiftUI
import simd

/// How big the thing really is, settled by dragging its edge.
///
/// This is the half that actually damages the picture. A wrong label is a wrong
/// word; a wrong box is wrong geometry, and the geometry is what the picture is
/// built on — 0.6 m against 1.2 m is not something anyone says in words.
struct RoomSizeView: View {
    @Bindable var room: ScannedRoom
    let objectID: UUID
    @Binding var path: [RoomIdentityRoute]

    @Environment(\.roomAccent) private var accent

    @State private var captured: CapturedRoom?
    @State private var axis: ScannedPlanView.Axis = .width
    /// Width, height, depth in metres, live while dragging.
    @State private var size: SIMD3<Float> = .zero
    @State private var shift: SIMD2<Float> = .zero
    @State private var ready = false

    private var scanned: RoomReading.Object? {
        captured.map { room.reading(of: $0) }?.object(objectID)
    }

    /// The plan drawn from the working values, not the saved ones, so the box
    /// moves under the finger.
    private var workingPlan: FloorPlan? {
        guard let captured else { return nil }
        var corrections = room.corrections
        var correction = corrections[objectID]
        correction.widthMetres = size.x
        correction.heightMetres = size.y
        correction.depthMetres = size.z
        correction.centreShift = shift
        corrections[objectID] = correction
        return FloorPlan(room: captured, corrections: corrections)
    }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    question
                    planCard
                    offers
                    tabs
                }
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .navigationTitle(scanned.map { "The \($0.name)" } ?? "The size")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .task {
            guard !ready else { return }
            captured = room.rawCapturedRoom
            if let scanned {
                size = scanned.dimensions
                shift = scanned.centreShift
            }
            ready = true
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("How \(axis.label) is it,\nreally?")
                .question()
            Text("This box is literally what the picture is drawn around. A narrow box draws a narrow \(scanned?.name ?? "thing"), whatever you type.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    @ViewBuilder private var planCard: some View {
        if let workingPlan {
            VStack(alignment: .leading, spacing: 8) {
                ScannedPlanView(plan: workingPlan, focus: objectID,
                                resize: ScannedPlanView.Resize(
                                    axis: axis,
                                    metres: metresBinding,
                                    shift: $shift))
                    .frame(height: 228)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text(axis.isOnThePlan
                     ? "Drag the edge. The other side stays where the scan put it."
                     : "Height has no edge on a plan — use the offers below.")
                    .font(.system(size: 12))
                    .foregroundStyle(Paper.mutedInk)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    /// Writes the dragged axis back into the working size.
    private var metresBinding: Binding<Float> {
        Binding(get: { axis == .depth ? size.z : size.x },
                set: { value in
                    if axis == .depth { size.z = value } else { size.x = value }
                })
    }

    // MARK: - One-tap offers

    private var offers: some View {
        FlowLayout(spacing: 8) {
            ForEach(offered, id: \.label) { offer in
                ChoicePill(title: offer.label) { set(offer.metres) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private struct Offer { var label: String; var metres: Float }

    /// Measured off the plan rather than invented: "to the corner" is only
    /// meaningful as a real distance to a real wall.
    private var offered: [Offer] {
        guard let scanned else { return [] }
        var offers = [Offer(label: "Twice the scan", metres: current(of: scanned.scannedDimensions) * 2)]

        if let workingPlan, axis.isOnThePlan,
           let footprint = workingPlan.objects.first(where: { $0.id == objectID }) {
            let along = SIMD2(cos(footprint.rotation), sin(footprint.rotation))
            let direction = axis == .width ? along : SIMD2(-along.y, along.x)
            let extent = axis == .width ? footprint.size.x : footprint.size.y
            let anchor = footprint.centre - direction * (extent / 2)
            if let reach = PlanMeasure.distanceToWall(from: anchor, along: direction,
                                                      in: workingPlan), reach > 0.2 {
                offers.append(Offer(label: String(format: "To the wall — %.1f m", reach),
                                    metres: reach))
            }
        }

        if let workingPlan,
           let sofa = workingPlan.objects.first(where: { $0.id != objectID && $0.label == "Sofa" }) {
            offers.append(Offer(label: String(format: "As wide as the sofa — %.1f m", sofa.size.x),
                                metres: sofa.size.x))
        }
        return offers
    }

    private func current(of dimensions: SIMD3<Float>) -> Float {
        switch axis {
        case .width: return dimensions.x
        case .depth: return dimensions.z
        case .height: return dimensions.y
        }
    }

    /// Setting a size from a tap moves the same edge the drag would, so the two
    /// ways of answering agree.
    private func set(_ metres: Float) {
        guard let workingPlan,
              let footprint = workingPlan.objects.first(where: { $0.id == objectID }) else {
            if axis == .height { size.y = metres }
            return
        }
        switch axis {
        case .height:
            size.y = metres
        case .width, .depth:
            let along = SIMD2(cos(footprint.rotation), sin(footprint.rotation))
            let direction = axis == .width ? along : SIMD2(-along.y, along.x)
            let extent = axis == .width ? footprint.size.x : footprint.size.y
            let anchor = footprint.centre - direction * (extent / 2)
            if axis == .width { size.x = metres } else { size.z = metres }
            shift += anchor + direction * (metres / 2) - footprint.centre
        }
    }

    // MARK: - The three numbers

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(ScannedPlanView.Axis.allCases) { one in
                Button { axis = one } label: {
                    VStack(spacing: 2) {
                        Text(String(format: "%.2f m", value(of: one)))
                            .font(.system(size: 17, weight: axis == one ? .semibold : .regular))
                            .foregroundStyle(axis == one ? Paper.ink : Paper.quietInk)
                        Text(one.label)
                            .font(.system(size: 12))
                            .foregroundStyle(axis == one ? accent : Paper.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        if axis == one {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Paper.card)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(accent, lineWidth: 2))
                                .shadow(color: Paper.cardShadow, radius: 1.5, x: 0, y: 1)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Paper.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func value(of one: ScannedPlanView.Axis) -> Float {
        switch one {
        case .width: return size.x
        case .depth: return size.z
        case .height: return size.y
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(untouched)
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("Save the size", action: save)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Paper.sheet)
    }

    /// Names only the sides nobody is touching. The side being edited is never
    /// "left alone", even before it has moved.
    private var untouched: String {
        guard let scanned else { return "" }
        let left = ScannedPlanView.Axis.allCases.filter { one in
            one != axis
                && abs(value(of: one) - current(of: scanned.scannedDimensions, axis: one)) < 0.005
        }
        guard !left.isEmpty else { return "All three sides are being changed." }
        let names = left.map(\.label)
        return "\(ListFormatter.localizedString(byJoining: names).capitalizedFirst) looked right, so \(left.count == 1 ? "it is" : "they are") left alone."
    }

    private func current(of dimensions: SIMD3<Float>, axis: ScannedPlanView.Axis) -> Float {
        switch axis {
        case .width: return dimensions.x
        case .depth: return dimensions.z
        case .height: return dimensions.y
        }
    }

    /// A measurement equal to the scan's is stored as no correction at all, so
    /// "has the user changed this" stays an honest question.
    private func save() {
        guard let scanned else { return }
        room.correctObject(objectID) { correction in
            correction.widthMetres = near(size.x, scanned.scannedDimensions.x) ? nil : size.x
            correction.heightMetres = near(size.y, scanned.scannedDimensions.y) ? nil : size.y
            correction.depthMetres = near(size.z, scanned.scannedDimensions.z) ? nil : size.z
            correction.centreShift = simd_length(shift) < 0.005 ? nil : shift
        }
        path.append(.ideas)
    }

    private func near(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 0.005 }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
