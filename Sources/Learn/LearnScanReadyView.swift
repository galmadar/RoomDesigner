import SwiftUI

/// The plan of the walk, before the camera opens.
///
/// The only screen in the app that blocks, and it earns it: a thin scan cannot
/// be repaired afterwards, only walked again.
struct LearnScanReadyView: View {
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 16))
                        .foregroundStyle(Paper.secondaryInk)
                        .frame(minWidth: 48, minHeight: 44, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Walk the walls.").question()
                            Text("The pictures can only be as good as the scan. Three things matter.")
                                .font(.system(size: 14))
                                .foregroundStyle(Paper.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        WalkPlanDiagram()
                            .frame(height: 214)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)

                        VStack(alignment: .leading, spacing: 16) {
                            rule(1, "Go slowly",
                                 "About one step a second. Rushing leaves the walls soft.")
                            rule(2, "Point at the walls",
                                 "Not only the furniture. The walls are what hold a picture together.")
                            rule(3, "Look into every corner",
                                 "Corners are where the walls get joined up.")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 16)
                }

                VStack(spacing: 11) {
                    Button("Start scanning", action: onStart)
                        .buttonStyle(PrimaryButtonStyle())
                    Text("You can stop and scan again whenever you like.")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
    }

    private func rule(_ number: Int, _ heading: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Paper.mutedInk)
                .frame(width: 26, height: 26)
                .background(Paper.outline, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(heading)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.16)
                    .foregroundStyle(Paper.ink)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The walk, drawn: the room, the path that keeps near the walls, and the four
/// corners it turns into.
private struct WalkPlanDiagram: View {
    @Environment(\.roomAccent) private var accent

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let room = CGRect(x: 30, y: 22, width: size.width - 60, height: size.height - 44)
            let path = room.insetBy(dx: 22, dy: 22)

            ZStack(alignment: .topLeading) {
                Rectangle().fill(Paper.tint)

                Rectangle()
                    .strokeBorder(Paper.ink, lineWidth: 2.5)
                    .frame(width: room.width, height: room.height)
                    .offset(x: room.minX, y: room.minY)

                // A window on one wall and a door on another, so the room reads
                // as a room rather than as a box.
                Capsule().fill(Paper.mutedInk.opacity(0.7))
                    .frame(width: 7, height: 62)
                    .offset(x: room.minX - 3, y: room.minY + 44)
                Capsule().fill(Paper.outline)
                    .frame(width: 7, height: 40)
                    .offset(x: room.maxX - 4, y: room.minY + room.height * 0.55)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Paper.outline)
                    .frame(width: min(112, room.width * 0.38), height: 44)
                    .offset(x: room.midX - 56, y: room.midY - 22)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .frame(width: path.width, height: path.height)
                    .offset(x: path.minX, y: path.minY)

                ForEach(corners(of: path), id: \.self) { corner in
                    Circle()
                        .fill(accent)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Paper.tint, lineWidth: 2))
                        .offset(x: corner.x - 5.5, y: corner.y - 5.5)
                }

                Circle()
                    .fill(accent)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Paper.sheet, lineWidth: 3))
                    .offset(x: path.midX - 9, y: path.minY - 9)

                // Clear of the lines: a label struck through by the path it is
                // naming reads as a mistake.
                label("you", at: CGPoint(x: path.midX + 16, y: path.minY - 20))
                label("keep near the walls", at: CGPoint(x: path.minX + 2, y: path.maxY + 4))
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .accessibilityElement()
        .accessibilityLabel("A plan of the room with a path just inside the walls, turning into each of the four corners.")
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    private func label(_ text: String, at point: CGPoint) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Paper.mutedInk)
            .offset(x: point.x, y: point.y)
    }
}
