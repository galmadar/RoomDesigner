import RoomPlan
import SwiftUI

struct RoomDetailView: View {
    @Bindable var room: ScannedRoom

    @State private var yaw: Double = 0
    @State private var conditioning: ConditioningImages.Kind = .depth
    @State private var preview: UIImage?
    @State private var brief = ""
    @State private var strength: Double = 1.0
    @State private var isGenerating = false
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let captured = room.capturedRoom {
                    FloorPlanView(plan: FloorPlan(room: captured))
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    viewpoint(captured)
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
        .task { render() }
    }

    private func viewpoint(_ captured: CapturedRoom) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Viewpoint").font(.headline)

            if let preview {
                Image(uiImage: preview)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Picker("Conditioning", selection: $conditioning) {
                ForEach(ConditioningImages.Kind.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: conditioning) { render() }

            HStack {
                Image(systemName: "arrow.clockwise")
                Slider(value: $yaw, in: 0...360, step: 5) { editing in
                    if !editing { render() }
                }
                Text("\(Int(yaw))°").monospacedDigit().frame(width: 44)
            }
        }
    }

    private var designBrief: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    HStack { ProgressView(); Text("Designing…") }
                } else {
                    Text("Design this room")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(brief.isEmpty || preview == nil || isGenerating)
        }
    }

    @ViewBuilder private var results: some View {
        if !room.conceptImages.isEmpty {
            Text("Concepts").font(.headline)
            ForEach(Array(room.conceptImages.enumerated()), id: \.offset) { _, data in
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func render() {
        guard let captured = room.capturedRoom else { return }
        let mesh = RoomGeometry.build(from: captured)
        guard !mesh.isEmpty, let renderer = try? Renderer() else { return }

        let camera = Camera.standing(in: mesh.bounds, yaw: Float(yaw) * .pi / 180)
        guard let buffers = try? renderer.render(mesh, camera: camera) else { return }
        preview = ConditioningImages.image(conditioning, from: buffers)
    }

    private func generate() async {
        guard let preview else { return }
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
