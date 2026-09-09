import RoomPlan
import SwiftUI
import simd

struct RoomDetailView: View {
    @Bindable var room: ScannedRoom

    @StateObject private var previews = PreviewRenderer()
    @State private var isDragging = false
    @State private var cameraPosition: SIMD2<Float> = .zero
    @State private var yaw: Float = 0
    @State private var conditioning: ConditioningImages.Kind = .depth
    @State private var brief = ""
    @State private var strength: Double = 1.0
    @State private var isGenerating = false
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let captured = room.capturedRoom {
                    viewpoint(FloorPlan(room: captured))
                    framing
                    designBrief
                    results
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
        .task { prepare() }
        .onChange(of: cameraPosition) { render() }
        .onChange(of: yaw) { render() }
        .onChange(of: conditioning) { render() }
        .onChange(of: isDragging) { if !isDragging { render() } }   // sharpen on release
    }

    private func viewpoint(_ plan: FloorPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where you're standing").font(.headline)
            Text("Drag the dot to move. Drag the small circle to turn. The shaded wedge is what ends up in the picture.")
                .font(.caption)
                .foregroundStyle(.secondary)

            CameraPlanPicker(plan: plan, position: $cameraPosition,
                             yaw: $yaw, isDragging: $isDragging)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
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
            Text("Concepts").font(.headline)
            ForEach(Array(room.conceptImages.enumerated().reversed()), id: \.offset) { _, data in
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        previews.request(position: cameraPosition, yaw: yaw,
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
            room.brief = brief
            room.conceptImages.append(contentsOf: images.compactMap { $0.pngData() })
        } catch {
            failure = error.localizedDescription
        }
    }
}
