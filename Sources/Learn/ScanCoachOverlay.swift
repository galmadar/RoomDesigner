import SwiftUI

/// What is drawn over the live camera while a room is being scanned: the walls
/// as they are found, the corner that has not been joined yet, and at most one
/// line of correction.
struct ScanCoachOverlay: View {
    @ObservedObject var coach: ScanCoach
    let photoCount: Int
    let isFinishing: Bool
    let onCancel: () -> Void
    let onShutter: () -> Void
    let onFinish: () -> Void

    /// Five times a second is enough for a mark on a wall, and cheap enough
    /// that it can never be why a capture stutters.
    private let clock = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            marker
            VStack(spacing: 0) {
                topBar
                HStack {
                    Spacer(minLength: 0)
                    wallsFound
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Spacer(minLength: 0)
                bottom
            }
        }
        .onReceive(clock) { _ in coach.refreshAim() }
    }

    // MARK: - Chrome

    private var topBar: some View {
        ZStack {
            Text("Scanning")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Cancel the scan")
                Spacer(minLength: 0)
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background(
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top))
    }

    /// One bar per wall RoomPlan has found, lit once it has been joined into
    /// its corners. A row rather than the plan of a room: a scan can turn up
    /// five walls or three, and a drawn rectangle would be a claim about the
    /// shape of the room that the scan has not made yet.
    private var wallsFound: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                if coach.progress.found == 0 {
                    ForEach(0..<4, id: \.self) { _ in bar(lit: false) }
                } else {
                    ForEach(0..<min(coach.progress.found, 8), id: \.self) { index in
                        bar(lit: index < coach.progress.joined)
                    }
                }
            }
            Text(wallsLabel)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(wallsLabel)
    }

    private func bar(lit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(lit ? Paper.fallbackAccent : Color.white.opacity(0.26))
            .frame(width: 16, height: 3)
    }

    private var wallsLabel: String {
        guard coach.progress.found > 0 else { return "Looking for walls" }
        return "\(coach.progress.joined) of \(coach.progress.found) walls"
    }

    // MARK: - The corner that is not joined yet

    @ViewBuilder private var marker: some View {
        if let aim = coach.aim {
            GeometryReader { geometry in
                let point = place(aim, imageAspect: coach.aimAspect, in: geometry.size)
                ZStack {
                    Circle()
                        .strokeBorder(Paper.fallbackAccent.opacity(0.9), lineWidth: 2)
                        .background(Circle().fill(Paper.fallbackAccent.opacity(0.16)))
                        .frame(width: 52, height: 52)
                    Circle().fill(Paper.fallbackAccent).frame(width: 8, height: 8)
                    Text("not yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .offset(y: 40)
                }
                .position(point)
                .allowsHitTesting(false)
            }
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    /// RoomPlan's feed fills the view, so the image is cropped on one axis. The
    /// same fill has to be applied here or the mark lands beside the corner it
    /// is pointing at rather than on it.
    private func place(_ point: CGPoint, imageAspect: CGFloat, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0, imageAspect > 0 else { return .zero }
        let viewAspect = size.width / size.height
        let spanX = imageAspect > viewAspect ? size.height * imageAspect : size.width
        let spanY = imageAspect > viewAspect ? size.height : size.width / imageAspect
        return CGPoint(x: (point.x - 0.5) * spanX + size.width / 2,
                       y: (point.y - 0.5) * spanY + size.height / 2)
    }

    // MARK: - Correction, shutter and finish

    private var bottom: some View {
        VStack(spacing: 14) {
            if let correction = coach.correction {
                HStack(spacing: 13) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Paper.fallbackAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(correction.title)
                            .font(.system(size: 18, weight: .semibold))
                            .tracking(-0.18)
                            .foregroundStyle(.white)
                        Text(correction.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 15)
                .background(.black.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }

            HStack(alignment: .bottom) {
                Spacer(minLength: 0)
                if !isFinishing { ShutterButton(count: photoCount, action: onShutter) }
            }

            VStack(spacing: 9) {
                Button(action: onFinish) {
                    Text(isFinishing ? "Finishing…" : "Finish scan")
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.18)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(.white.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(isFinishing)
                Text(finishNote)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .animation(.easeOut(duration: 0.2), value: coach.correction)
    }

    private var finishNote: String {
        switch coach.unjoined {
        case 0 where coach.progress.found == 0:
            return "No walls found yet. Point the phone at one and walk along it."
        case 0:
            return "Every wall is joined into its corners."
        case 1:
            return "One wall still to go. Finishing now leaves it thin."
        default:
            return "\(coach.unjoined) walls still to go. Finishing now leaves them thin."
        }
    }
}
