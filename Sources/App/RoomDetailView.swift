import RoomPlan
import SwiftUI
import simd

struct RoomDetailView: View {
    @Bindable var room: ScannedRoom

    @StateObject private var previews = PreviewRenderer()
    @State private var isDragging = false
    @State private var cameraPosition: SIMD2<Float> = .zero
    @State private var yaw: Float = 0
    @State private var fieldOfView: Float = 65 * .pi / 180
    @State private var conditioning: ConditioningImages.Kind = .depth
    @State private var brief = ""
    @State private var strength: Double = 1.0
    @State private var isGenerating = false
    @State private var failure: String?
    @State private var enlarged: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let captured = room.capturedRoom {
                    results
                    viewpoint(FloorPlan(room: captured))
                    framing
                    designBrief
                } else {
                    ContentUnavailableView("Nothing scanned", systemImage: "questionmark")
                }
            }
            .padding()
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't generate", isPresented: .constant(failure != nil)) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
        .fullScreenCover(item: $enlarged) { image in
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image).resizable().scaledToFit()
            }
            .onTapGesture { enlarged = nil }
        }
        .task { prepare() }
        .onChange(of: cameraPosition) { render() }
        .onChange(of: yaw) { render() }
        .onChange(of: conditioning) { render() }
        .onChange(of: fieldOfView) { render() }
        .onChange(of: isDragging) { if !isDragging { render() } }   // sharpen on release
    }

    private func viewpoint(_ plan: FloorPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where you're standing").font(.headline)
            Text("Drag the dot to move. Drag the small circle to turn. The shaded wedge is what ends up in the picture.")
                .font(.caption)
                .foregroundStyle(.secondary)

            CameraPlanPicker(plan: plan, position: $cameraPosition,
                             yaw: $yaw, isDragging: $isDragging,
                             fieldOfView: $fieldOfView)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            lens
        }
    }

    private var lens: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.left.and.right.square")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: Binding(get: { Double(fieldOfView) },
                                          set: { fieldOfView = Float($0) }),
                           in: Double(30 * Float.pi / 180)...Double(110 * Float.pi / 180))
                    Text("Lens \(Int(fieldOfView * 180 / .pi))° — \(lensDescription)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .foregroundStyle(.secondary)
                Button { dolly(-0.35) } label: {
                    Label("Back", systemImage: "minus.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                Button { dolly(0.35) } label: {
                    Label("Closer", systemImage: "plus.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
        }
    }

    private var lensDescription: String {
        let degrees = fieldOfView * 180 / .pi
        if degrees < 45 { return "tight, picks out one corner" }
        if degrees < 75 { return "natural, like your eyes" }
        return "wide, makes the room feel bigger"
    }

    /// Steps along the way the camera is facing, so Back and Closer mean what
    /// you are looking at, not a compass direction.
    private func dolly(_ metres: Float) {
        guard let bounds = previews.bounds else { return }
        let heading = SIMD2(sin(yaw), -cos(yaw))
        cameraPosition = Camera.clamp(cameraPosition + heading * metres, in: bounds)
    }

    private var framing: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = previews.image {
                Image(uiImage: preview)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 200)
                    .overlay(ProgressView())
            }

            Picker("Conditioning", selection: $conditioning) {
                ForEach(ConditioningImages.Kind.allCases) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var designBrief: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The redesign").font(.headline)
            TextField("Scandinavian bedroom, oak floor, morning light",
                      text: $brief, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                Text("Hold the room").font(.caption)
                Slider(value: $strength, in: 0.2...1.0)
                Text(String(format: "%.1f", strength)).monospacedDigit().frame(width: 32)
            }

            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    HStack { ProgressView(); Text("Designing…") }.frame(maxWidth: .infinity)
                } else {
                    Text("Design this room").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(brief.isEmpty || previews.image == nil || isGenerating)
        }
    }

    @ViewBuilder private var results: some View {
        if !room.conceptImages.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("^[\(room.conceptImages.count) design](inflect: true)")
                    .font(.headline)

                ForEach(Array(room.conceptImages.enumerated()).reversed(), id: \.offset) { pair in
                    if let image = UIImage(data: pair.element) {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { enlarged = image }
                    }
                }
            }
        }
    }

    private func prepare() {
        guard previews.bounds == nil, let captured = room.capturedRoom else { return }
        let built = RoomGeometry.build(from: captured)
        previews.load(built)
        cameraPosition = Camera.centre(of: built.bounds)
        render()
    }

    private func render() {
        previews.request(position: cameraPosition, yaw: yaw, fieldOfView: fieldOfView,
                         kind: conditioning, draft: isDragging)
    }

    private func generate() async {
        guard let preview = previews.image else { return }
        isGenerating = true
        defer { isGenerating = false }

        do {
            let images = try await PlanService().generate(
                from: preview,
                brief: .init(prompt: brief, strength: Float(strength), conditioning: conditioning)
            )
            let encoded = images.compactMap { $0.pngData() }
            guard !encoded.isEmpty else {
                failure = "The design came back but the pictures could not be read."
                return
            }
            room.brief = brief
            room.conceptImages = room.conceptImages + encoded
        } catch {
            failure = error.localizedDescription
        }
    }
}


/// So a tapped concept can drive `fullScreenCover(item:)`.
extension UIImage: @retroactive Identifiable {
    public var id: Int { hashValue }
}
