import MetalKit
import SwiftUI
import simd

/// Standing inside the scan at eye height and walking around it.
///
/// The room here is the same geometry the design flow renders, drawn live
/// instead of once: the walls, floor, ceiling, doors and windows that were
/// measured, plus whatever is standing on the floor plan. Nothing is invented.
struct WalkView: View {
    let room: ScannedRoom

    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomAccent) private var accent

    @StateObject private var walk = WalkState()
    @State private var comparing: Int?
    /// The view the shutter was pressed on, while the design flow is open on it.
    @State private var designing: Standing?
    @State private var blend: Double = 1
    @State private var lastDrag: CGSize = .zero
    @State private var pinchStart: Float?

    private var photos: [ScanPhoto] { room.sortedPhotos }

    private var comparedPhoto: ScanPhoto? {
        comparing.flatMap { photos.indices.contains($0) ? photos[$0] : nil }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let renderer = walk.renderer {
                room3D(renderer)
            } else if walk.isReady {
                nothingToWalk
            } else {
                ProgressView().tint(.white)
            }

            if walk.hasRoom {
                if comparing == nil { chrome } else { compareChrome }
            }
        }
        .statusBarHidden()
        .tint(accent)
        .task { await walk.load(room) }
        // Opened over the room rather than instead of it: the flow hands the
        // picture off and closes, and you are still standing where you shot it.
        .fullScreenCover(item: $designing) { standing in
            DesignFlowView(room: room, standing: standing)
                .environment(\.roomAccent, accent)
        }
    }

    // MARK: - The room

    /// One Metal view for the life of the screen, resized rather than replaced:
    /// while comparing it is letterboxed to the photo's shape, so the render and
    /// the photo cover exactly the same field of view.
    private func room3D(_ renderer: WalkRenderer) -> some View {
        GeometryReader { geometry in
            let size = frame(in: geometry.size)
            ZStack {
                MetalRoomView(renderer: renderer)
                    .frame(width: size.width, height: size.height)
                if let photo = comparedPhoto, let image = photo.uprightImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .opacity(blend)
                        .allowsHitTesting(false)
                }
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .ignoresSafeArea()
        .overlay { if comparing == nil { lookLayer } }
    }

    private func frame(in available: CGSize) -> CGSize {
        guard let aspect = comparedPhoto?.viewpoint?.aspect, aspect > 0 else { return available }
        let fitted = CGFloat(aspect)
        return available.width / available.height > fitted
            ? CGSize(width: available.height * fitted, height: available.height)
            : CGSize(width: available.width, height: available.width / fitted)
    }

    /// Drag anywhere that is not a control to look around; pinch to change height.
    private var lookLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        walk.look(by: CGSize(width: value.translation.width - lastDrag.width,
                                             height: value.translation.height - lastDrag.height))
                        lastDrag = value.translation
                    }
                    .onEnded { _ in lastDrag = .zero }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? walk.eyeHeight
                        pinchStart = start
                        walk.setEyeHeight(start * Float(value.magnification))
                    }
                    .onEnded { _ in pinchStart = nil }
            )
            .accessibilityLabel("Look around")
    }

    private var nothingToWalk: some View {
        VStack(spacing: 10) {
            Text("Nothing to walk through")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("This room has no scan to stand inside.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            Button("Close") { dismiss() }
                .font(.system(size: 16))
                .padding(.top, 8)
        }
        .padding(24)
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                ThumbStick { walk.walk = $0 }
                Spacer(minLength: 12)
                HeightSlider(height: walk.eyeHeight,
                             range: WalkState.lowestEye...WalkState.highestEye) {
                    walk.setEyeHeight($0)
                }
            }
            .padding(.horizontal, 20)
            bottomBand
        }
    }

    /// The shutter, with the photo spots running alongside it — a camera's
    /// shutter and the strip of what it has already taken.
    ///
    /// It sits here rather than in the gap between the stick and the height
    /// slider because that gap is the one piece of chrome still free for a
    /// control that has to be dragged, and a shutter is only ever tapped.
    private var bottomBand: some View {
        HStack(alignment: .bottom, spacing: 0) {
            photoSpots
                .frame(maxWidth: .infinity, alignment: .leading)
            WalkShutterButton { designing = walk.standing }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Paper.ink)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Close")

            Text(room.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Paper.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(.regularMaterial, in: Capsule())

            Spacer(minLength: 0)

            Text(heightLabel)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(Paper.secondaryInk)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.regularMaterial, in: Capsule())
                .accessibilityLabel("Eye height \(heightLabel)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var heightLabel: String {
        String(format: "%.2f m", walk.eyeHeight)
    }

    /// Standing where a photo was taken is one tap; comparing it is the next.
    @ViewBuilder private var photoSpots: some View {
        if photos.isEmpty {
            Text(walk.stopsAtWalls
                 ? "Drag to look. The stick walks you around the room."
                 : "Drag to look. This scan has no floor outline, so walking is not held to the walls.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
        } else {
            VStack(spacing: 10) {
                if let standing = walk.standingAt {
                    Button {
                        blend = 1
                        comparing = standing
                        walk.compare(with: photos[standing])
                    } label: {
                        Label("Compare with photo \(standing + 1)", systemImage: "rectangle.on.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Paper.ink)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos.indices, id: \.self) { index in
                            spotTile(index)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
    }

    private func spotTile(_ index: Int) -> some View {
        let standing = walk.standingAt == index
        return Button {
            walk.stand(at: photos[index], index: index)
        } label: {
            FilledImage(image: photos[index].thumbnail)
                .frame(width: 76, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(standing ? accent : .white.opacity(0.35),
                                      lineWidth: standing ? 3 : 1)
                }
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(standing ? accent : Color.black.opacity(0.55), in: Circle())
                        .padding(4)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stand at photo \(index + 1)")
        .accessibilityAddTraits(standing ? .isSelected : [])
    }

    // MARK: - Comparing

    /// The render and the photo, from the same spot through the same lens. The
    /// slider crosses between them, so the walls either line up or they do not.
    private var compareChrome: some View {
        VStack {
            HStack {
                Button {
                    comparing = nil
                    walk.compare(with: nil)
                } label: {
                    Label("Done", systemImage: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                HStack {
                    Text("Scan").font(.system(size: 13)).foregroundStyle(Paper.secondaryInk)
                    Slider(value: $blend, in: 0...1)
                        .accessibilityLabel("Blend between the scan and the photo")
                    Text("Photo").font(.system(size: 13)).foregroundStyle(Paper.secondaryInk)
                }
                Text("Both are drawn from where photo \((comparing ?? 0) + 1) was taken.")
                    .font(.system(size: 12))
                    .foregroundStyle(Paper.secondaryInk)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - The Metal view

private struct MetalRoomView: UIViewRepresentable {
    let renderer: WalkRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        renderer.configure(view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}
}

// MARK: - Controls

/// Walking, under the left thumb.
///
/// A stick rather than tap-to-move or a walk-forward toggle: it is the one
/// first-person control everyone already knows, it gives speed and strafing in
/// the same gesture, it can back you out of a corner, and it costs only its own
/// footprint — the rest of the screen stays free for looking, which is what the
/// screen is actually for.
private struct ThumbStick: View {
    var onChange: (SIMD2<Float>) -> Void

    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().strokeBorder(Paper.secondaryInk.opacity(0.35), lineWidth: 1)
            Image(systemName: "figure.walk")
                .font(.system(size: 15))
                .foregroundStyle(Paper.secondaryInk.opacity(knob == .zero ? 0.8 : 0))
            Circle()
                .fill(Paper.ink.opacity(0.5))
                .frame(width: 36, height: 36)
                .offset(knob)
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let reach = max(hypot(value.translation.width, value.translation.height), 0.001)
                    let limit = reach > radius ? radius / reach : 1
                    knob = CGSize(width: value.translation.width * limit,
                                  height: value.translation.height * limit)
                    onChange(SIMD2(Float(knob.width / radius), Float(-knob.height / radius)))
                }
                .onEnded { _ in
                    knob = .zero
                    onChange(.zero)
                }
        )
        // Drawn from shapes, which are invisible to VoiceOver until asked.
        .accessibilityElement()
        .accessibilityLabel("Walk")
    }
}

/// Eye height, on the right edge where a thumb reaches without covering the room.
private struct HeightSlider: View {
    let height: Float
    let range: ClosedRange<Float>
    var onChange: (Float) -> Void

    private let track: CGFloat = 170

    var body: some View {
        let span = range.upperBound - range.lowerBound
        let fraction = CGFloat((height - range.lowerBound) / max(span, 0.001))
        return ZStack(alignment: .bottom) {
            Capsule().fill(.regularMaterial)
            Capsule()
                .fill(Paper.ink.opacity(0.4))
                .frame(height: max(20, track * fraction))
        }
        .frame(width: 36, height: track)
        .overlay(alignment: .top) {
            Image(systemName: "eye")
                .font(.system(size: 12))
                .foregroundStyle(Paper.secondaryInk)
                .padding(.top, 7)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let from = 1 - min(max(value.location.y / track, 0), 1)
                    onChange(range.lowerBound + Float(from) * span)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Eye height")
        .accessibilityValue(String(format: "%.2f metres", height))
    }
}
