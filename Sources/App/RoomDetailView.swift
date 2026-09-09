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
    @State private var mode: CameraPlanPicker.Mode = .camera
    @State private var selection: Proposal.ID?

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
        .onChange(of: room.proposalsData) { rebuild() }
        .onChange(of: isDragging) { if !isDragging { render() } }   // sharpen on release
    }

    private func viewpoint(_ plan: FloorPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $mode) {
                Text("Camera").tag(CameraPlanPicker.Mode.camera)
                Text("Furniture").tag(CameraPlanPicker.Mode.furniture)
            }
            .pickerStyle(.segmented)

            Text(mode == .camera
                 ? "Drag the dot to move. Drag the small circle to turn. The shaded wedge is what ends up in the picture."
                 : "Add a piece below, then drag it into place. The thick edge is its front.")
                .font(.caption)
                .foregroundStyle(.secondary)

            CameraPlanPicker(plan: plan, mode: mode, position: $cameraPosition,
                             yaw: $yaw, isDragging: $isDragging,
                             fieldOfView: $fieldOfView,
                             proposals: proposalsBinding, selection: $selection)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if mode == .camera { lens } else { furniture }
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

    // MARK: - Furniture

    /// Always writes the whole array back: SwiftData does not reliably observe
    /// an in-place mutation of a stored collection.
    private var proposalsBinding: Binding<[Proposal]> {
        Binding(get: { room.proposals }, set: { room.proposals = $0 })
    }

    private var selectedProposal: Proposal? {
        room.proposals.first { $0.id == selection }
    }

    private var furniture: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Furniture.Kind.allCases) { kind in
                        Button { add(kind) } label: {
                            VStack(spacing: 3) {
                                Image(systemName: kind.symbol).font(.system(size: 17))
                                Text(kind.label).font(.caption2)
                            }
                            .frame(width: 62, height: 52)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 1)
            }

            if let selected = selectedProposal {
                HStack(spacing: 8) {
                    Button { turn(selected, by: -.pi / 12) } label: {
                        Image(systemName: "rotate.left")
                    }
                    Button { turn(selected, by: .pi / 12) } label: {
                        Image(systemName: "rotate.right")
                    }
                    Button { resize(selected, by: 0.9) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Button { resize(selected, by: 1.1) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    Spacer()
                    Text(dimensions(of: selected)).font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) { remove(selected) } label: {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.bordered)
            } else if !room.proposals.isEmpty {
                Text("Tap a piece on the plan to turn, resize or remove it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func dimensions(of proposal: Proposal) -> String {
        String(format: "%.2f × %.2f m", proposal.size.x, proposal.size.z)
    }

    /// New pieces land in front of the camera rather than at the origin, so they
    /// arrive already in shot.
    private func add(_ kind: Furniture.Kind) {
        guard let bounds = previews.bounds else { return }
        let ahead = cameraPosition + SIMD2(sin(yaw), -cos(yaw)) * 2.0
        var proposal = Proposal(kind: kind, position: Camera.clamp(ahead, in: bounds))
        proposal.rotation = yaw + .pi        // facing back towards the camera
        room.proposals = room.proposals + [proposal]
        selection = proposal.id
        render()
    }

    private func turn(_ proposal: Proposal, by angle: Float) {
        mutate(proposal) { $0.rotation += angle }
    }

    private func resize(_ proposal: Proposal, by factor: Float) {
        mutate(proposal) { $0.size = simd_clamp($0.size * factor,
                                                SIMD3(repeating: 0.1),
                                                SIMD3(repeating: 4.0)) }
    }

    private func remove(_ proposal: Proposal) {
        room.proposals = room.proposals.filter { $0.id != proposal.id }
        selection = nil
        render()
    }

    private func mutate(_ proposal: Proposal, _ change: (inout Proposal) -> Void) {
        guard let index = room.proposals.firstIndex(where: { $0.id == proposal.id })
        else { return }
        var updated = room.proposals
        change(&updated[index])
        room.proposals = updated
        render()
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
        let built = RoomGeometry.build(from: captured, proposals: room.proposals)
        previews.load(built)
        cameraPosition = Camera.centre(of: built.bounds)
        render()
    }

    private func rebuild() {
        guard let captured = room.capturedRoom else { return }
        previews.load(RoomGeometry.build(from: captured, proposals: room.proposals))
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
