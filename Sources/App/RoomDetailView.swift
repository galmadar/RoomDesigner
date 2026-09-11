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
    @State private var pitch: Float = 0
    @State private var eyeHeight: Float = 1.5
    @State private var conditioning: ConditioningImages.Kind = .room
    @State private var brief = ""
    @State private var strength: Double = 1.0
    @State private var isGenerating = false
    @State private var failure: String?
    @State private var enlarged: UIImage?
    @State private var mode: CameraPlanPicker.Mode = .camera
    @State private var selection: Proposal.ID?
    @State private var undoStack: [[Proposal]] = []
    @State private var redoStack: [[Proposal]] = []
    @State private var isNamingArrangement = false
    @State private var arrangementName = ""
    @State private var suggestions: [String] = []
    @State private var isSuggesting = false
    @State private var suggestionsFailed = false

    /// How many of the stored images came from the run that just finished, so
    /// that set can be shown together. View state, not stored: it only matters
    /// while you are looking at the designs you just asked for.
    @State private var latestCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let captured = room.capturedRoom {
                    results
                    ScanPhotosSection(room: room)
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
        .alert("Keep this arrangement", isPresented: $isNamingArrangement) {
            TextField("Name", text: $arrangementName)
            Button("Keep") { keepArrangement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the furniture as it stands now, so you can come back to it after trying something else.")
        }
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
        .onChange(of: pitch) { render() }
        .onChange(of: eyeHeight) { render() }
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
                 ? "Drag the dot to move. Drag the small circle to turn. Pinch to zoom, double-tap to fit."
                 : "Add a piece below, then drag it into place. The thick edge is its front. Pinch to zoom.")
                .font(.caption)
                .foregroundStyle(.secondary)

            CameraPlanPicker(plan: plan, mode: mode, position: $cameraPosition,
                             yaw: $yaw, isDragging: $isDragging,
                             fieldOfView: $fieldOfView,
                             proposals: proposalsBinding, selection: $selection,
                             onBeginEdit: { checkpoint() })
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
                Image(systemName: "figure.stand").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: Binding(get: { Double(eyeHeight) },
                                          set: { eyeHeight = Float($0) }),
                           in: 0.4...2.2)
                    Text("Eye height \(eyeHeight, format: .number.precision(.fractionLength(2))) m — \(heightDescription)")
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

            history
            saved
        }
    }

    private var history: some View {
        HStack(spacing: 8) {
            Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(undoStack.isEmpty)
            Button { redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(redoStack.isEmpty)
            Spacer()
            Button { arrangementName = suggestedName; isNamingArrangement = true } label: {
                Label("Keep", systemImage: "bookmark")
            }
            .disabled(room.proposals.isEmpty)
            Button(role: .destructive) { clearAll() } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(room.proposals.isEmpty)
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .font(.body)
    }

    @ViewBuilder private var saved: some View {
        if !room.arrangements.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Kept arrangements").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(room.arrangements) { arrangement in
                            Button { restore(arrangement) } label: {
                                VStack(spacing: 2) {
                                    Text(arrangement.name).font(.caption)
                                    Text("^[\(arrangement.proposals.count) piece](inflect: true)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .contextMenu {
                                Button(role: .destructive) { forget(arrangement) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
                Text("Tap to restore. Long-press to delete.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - History

    private var suggestedName: String { "Layout \(room.arrangements.count + 1)" }

    /// Snapshot the arrangement *before* it changes. Called at the start of a
    /// drag rather than during it, so one gesture is one undo step.
    private func checkpoint() {
        undoStack.append(room.proposals)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(room.proposals)
        apply(previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(room.proposals)
        apply(next)
    }

    private func apply(_ proposals: [Proposal]) {
        room.proposals = proposals
        if let selection, !proposals.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        rebuild()
    }

    private func clearAll() {
        checkpoint()
        room.proposals = []
        selection = nil
        rebuild()
    }

    private func keepArrangement() {
        let name = arrangementName.trimmingCharacters(in: .whitespaces)
        room.arrangements = room.arrangements
            + [Arrangement(name: name.isEmpty ? suggestedName : name,
                           proposals: room.proposals)]
    }

    private func restore(_ arrangement: Arrangement) {
        checkpoint()
        apply(arrangement.proposals)
    }

    private func forget(_ arrangement: Arrangement) {
        room.arrangements = room.arrangements.filter { $0.id != arrangement.id }
    }

    private func dimensions(of proposal: Proposal) -> String {
        String(format: "%.2f × %.2f m", proposal.size.x, proposal.size.z)
    }

    /// New pieces land in front of the camera rather than at the origin, so they
    /// arrive already in shot.
    private func add(_ kind: Furniture.Kind) {
        guard let bounds = previews.bounds else { return }
        let ahead = cameraPosition + SIMD2(sin(yaw), -cos(yaw)) * 2.0
        checkpoint()
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
        checkpoint()
        room.proposals = room.proposals.filter { $0.id != proposal.id }
        selection = nil
        render()
    }

    private func mutate(_ proposal: Proposal, _ change: (inout Proposal) -> Void) {
        checkpoint()
        guard let index = room.proposals.firstIndex(where: { $0.id == proposal.id })
        else { return }
        var updated = room.proposals
        change(&updated[index])
        room.proposals = updated
        render()
    }

    private var heightDescription: String {
        if eyeHeight < 0.8 { return "low, like sitting on the floor" }
        if eyeHeight < 1.3 { return "seated" }
        if eyeHeight < 1.8 { return "standing" }
        return "high, looking down into the room"
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
            ViewfinderView(image: previews.image, yaw: $yaw, pitch: $pitch,
                           isDragging: $isDragging)

            Picker("Conditioning", selection: $conditioning) {
                ForEach(ConditioningImages.Kind.allCases) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)

            if !conditioning.isConditioning {
                Text("The room as scanned — grey is what RoomPlan found, green is what you added. Designing from here uses the depth view.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var designBrief: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The redesign").font(.headline)
            TextField("Scandinavian bedroom, oak floor, morning light",
                      text: $brief, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            ideas

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

    /// Fetched once, when asked for. The detail view opens often and a network
    /// call every time would buy nothing; and if it fails the box is still a box.
    @ViewBuilder private var ideas: some View {
        if suggestions.isEmpty {
            Button {
                Task { await loadSuggestions() }
            } label: {
                if isSuggesting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Finding ideas…")
                    }
                } else {
                    Label(suggestionsFailed ? "Try again" : "Suggest ideas",
                          systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isSuggesting || room.capturedRoom == nil)

            if suggestionsFailed {
                Text("No ideas came back this time. Type your own.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { brief = suggestion } label: {
                            Text(suggestion)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3, reservesSpace: true)
                                .frame(width: 180, alignment: .topLeading)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(brief == suggestion ? Color.accentColor : Color.secondary)
                    }
                }
                .padding(.horizontal, 1)
            }
            Text("Tap an idea to use it, then edit it however you like.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func loadSuggestions() async {
        guard let captured = room.capturedRoom else { return }
        isSuggesting = true
        suggestionsFailed = false
        defer { isSuggesting = false }

        // Deliberately no alert: a missing suggestion is not an error the user
        // has to deal with, it just means typing the brief instead.
        let fetched = (try? await PlanService().suggestions(for: RoomFacts(room: captured))) ?? []
        suggestions = fetched
        suggestionsFailed = fetched.isEmpty
    }

    // MARK: - Results

    private struct Concept: Identifiable {
        let id: Int
        let image: UIImage
    }

    /// Newest first, so the run you just asked for is the first thing on screen.
    private var concepts: [Concept] {
        Array(room.conceptImages.enumerated().compactMap { index, data in
            UIImage(data: data).map { Concept(id: index, image: $0) }
        }.reversed())
    }

    private func grid(_ concepts: [Concept]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(concepts) { concept in
                Image(uiImage: concept.image)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { enlarged = concept.image }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if !room.conceptImages.isEmpty {
            let all = concepts
            let newest = Array(all.prefix(latestCount))
            let earlier = Array(all.dropFirst(latestCount))

            VStack(alignment: .leading, spacing: 10) {
                Text("^[\(room.conceptImages.count) design](inflect: true)")
                    .font(.headline)

                if !newest.isEmpty { grid(newest) }
                if !earlier.isEmpty {
                    if !newest.isEmpty {
                        Text("Earlier").font(.caption).foregroundStyle(.secondary)
                    }
                    grid(earlier)
                }

                Text("Tap a design to see it full screen.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func prepare() {
        guard previews.bounds == nil, let captured = room.capturedRoom else { return }
        let built = RoomGeometry.build(from: captured, proposals: room.proposals)
        previews.load(built)

        // Open on a shot worth looking at. Standing in the middle facing dead
        // level puts a blank wall in the frame; from a corner, angled slightly
        // down, you see the floor, the far corner and whatever is in between —
        // which is how a room actually gets photographed.
        let bounds = built.bounds
        let centre = Camera.centre(of: bounds)
        let corner = SIMD2(bounds.min.x + (bounds.max.x - bounds.min.x) * 0.18,
                           bounds.min.z + (bounds.max.z - bounds.min.z) * 0.18)
        cameraPosition = Camera.clamp(corner, in: bounds)
        let toCentre = centre - cameraPosition
        yaw = atan2(toCentre.x, -toCentre.y)
        pitch = -8 * .pi / 180
        render()
    }

    private func rebuild() {
        guard let captured = room.capturedRoom else { return }
        previews.load(RoomGeometry.build(from: captured, proposals: room.proposals))
        render()
    }

    private func render() {
        previews.request(position: cameraPosition, yaw: yaw, pitch: pitch,
                         eyeHeight: eyeHeight, fieldOfView: fieldOfView,
                         kind: conditioning, draft: isDragging)
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }

        // The solid view shows what was scanned; it is not something to condition
        // on, since its colours are invented. Fall back to depth.
        let kind: ConditioningImages.Kind = conditioning.isConditioning ? conditioning : .depth
        guard let conditioningImage = await previews.snapshot(
            position: cameraPosition, yaw: yaw, pitch: pitch, eyeHeight: eyeHeight,
            fieldOfView: fieldOfView, kind: kind)
        else {
            failure = "The viewpoint could not be rendered."
            return
        }

        do {
            let images = try await PlanService().generate(
                from: conditioningImage,
                brief: .init(prompt: brief, strength: Float(strength), conditioning: kind)
            )
            let encoded = images.compactMap { $0.pngData() }
            guard !encoded.isEmpty else {
                failure = "The design came back but the pictures could not be read."
                return
            }
            room.brief = brief
            latestCount = encoded.count
            // A fresh array, never append: SwiftData does not observe an
            // in-place mutation of a stored collection.
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
