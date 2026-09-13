import SwiftData
import SwiftUI
import simd

/// The floor plan and the furniture standing on it, on a screen of its own.
///
/// Today's editing, moved off the room screen unchanged: drag to move, tap to
/// select, then turn, resize or remove. Direct manipulation is the next slice.
struct LayoutView: View {
    let room: ScannedRoom

    @ObservedObject private var accents = RoomAccents.shared
    @StateObject private var thumbnails = ProductThumbnails()
    @Query(sort: \LibraryObject.createdAt, order: .reverse) private var library: [LibraryObject]

    @State private var selection: Proposal.ID?
    @State private var undoStack: [[Proposal]] = []
    @State private var redoStack: [[Proposal]] = []
    @State private var isPickingProduct = false
    @State private var isNamingArrangement = false
    @State private var arrangementName = ""

    private var accent: Color { accents.accent(for: room) }

    var body: some View {
        ZStack {
            Paper.sheet.ignoresSafeArea()
            if let captured = room.capturedRoom {
                content(FloorPlan(room: captured), bounds: RoomGeometry.build(from: captured).bounds)
            } else {
                unscanned
            }
        }
        .navigationTitle("Layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Paper.sheet, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isPickingProduct = true } label: {
                        Label("From the library", systemImage: "square.grid.2x2")
                    }
                    Divider()
                    ForEach(Furniture.Kind.allCases) { kind in
                        Button { add(kind) } label: { Label(kind.label, systemImage: kind.symbol) }
                    }
                } label: {
                    Text("Add").font(.system(size: 16)).foregroundStyle(accent)
                }
            }
        }
        .tint(accent)
        .environment(\.roomAccent, accent)
        .task { await accents.load(room) }
        .task(id: library.map(\.id)) { await thumbnails.load(library) }
        .sheet(isPresented: $isPickingProduct) {
            LibraryPicker(title: "Add from library",
                          footnote: "It lands in the middle of the room at its kind's usual size. Things with no floor shape, like a painting, go into a picture without being placed.",
                          unavailable: { $0.furnitureKind == nil ? "No floor shape. Set its kind in the Library to place it." : nil },
                          onPick: { add($0) })
        }
        .alert("Keep this arrangement", isPresented: $isNamingArrangement) {
            TextField("Name", text: $arrangementName)
            Button("Keep") { keepArrangement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the furniture as it stands now, so you can come back to it after trying something else.")
        }
    }

    private var unscanned: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("Nothing scanned")
                .question()
                .multilineTextAlignment(.center)
            Text("This room has no scan, so there is no floor to stand anything on.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private func content(_ plan: FloorPlan, bounds: (min: SIMD3<Float>, max: SIMD3<Float>)) -> some View {
        VStack(spacing: 12) {
            CameraPlanPicker(plan: plan, mode: .furniture,
                             position: .constant(Camera.centre(of: bounds)),
                             yaw: .constant(0), isDragging: .constant(false),
                             fieldOfView: .constant(65 * .pi / 180),
                             proposals: proposalsBinding, selection: $selection,
                             onBeginEdit: { checkpoint() },
                             links: planLinks,
                             canvas: Paper.tint,
                             showsCamera: false)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 4)

            Text(room.proposals.isEmpty
                 ? "Nothing on the plan yet. Add a piece, then drag it into place."
                 : "Drag a piece to move it. Tap it to turn, resize or remove it. The thick edge is its front.")
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            if let selected = selectedProposal { controls(selected) }

            saved

            history
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
        }
    }

    // MARK: - Pieces

    /// Always writes the whole array back: SwiftData does not reliably observe
    /// an in-place mutation of a stored collection.
    private var proposalsBinding: Binding<[Proposal]> {
        Binding(get: { room.proposals }, set: { room.proposals = $0 })
    }

    private var selectedProposal: Proposal? {
        room.proposals.first { $0.id == selection }
    }

    private var planLinks: [Proposal.ID: CameraPlanPicker.ProductLink] {
        Dictionary(PhotoDesignScene.placedProducts(room.proposals, library: library).map {
            ($0.id, CameraPlanPicker.ProductLink(name: $0.object.name,
                                                 thumbnail: thumbnails.images[$0.object.id],
                                                 marker: $0.marker))
        }, uniquingKeysWith: { first, _ in first })
    }

    private func controls(_ selected: Proposal) -> some View {
        HStack(spacing: 8) {
            if let link = planLinks[selected.id] {
                MarkerDot(marker: link.marker)
                Text(link.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
            } else {
                Text(selected.kind.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.ink)
            }
            Spacer(minLength: 0)
            plainAction("rotate.left") { turn(selected, by: -.pi / 12) }
            plainAction("rotate.right") { turn(selected, by: .pi / 12) }
            plainAction("minus.magnifyingglass") { resize(selected, by: 0.9) }
            plainAction("plus.magnifyingglass") { resize(selected, by: 1.1) }
            plainAction("trash", tint: Paper.destructive) { remove(selected) }
        }
        .padding(.horizontal, 20)
    }

    private func plainAction(_ symbol: String, tint: Color = Paper.quietInk,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Paper.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
    }

    private var history: some View {
        HStack(spacing: 10) {
            quiet("Undo", symbol: "arrow.uturn.backward") { undo() }
                .disabled(undoStack.isEmpty)
            quiet("Keep", symbol: "bookmark") {
                arrangementName = suggestedName
                isNamingArrangement = true
            }
            .disabled(room.proposals.isEmpty)
            quiet("Clear", symbol: "trash", tint: Paper.destructive) { clearAll() }
                .disabled(room.proposals.isEmpty)
        }
    }

    private func quiet(_ title: String, symbol: String, tint: Color = Paper.quietInk,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 16))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var saved: some View {
        if !room.arrangements.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved versions")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(room.arrangements) { arrangement in
                            Button { restore(arrangement) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(arrangement.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Paper.ink)
                                    Text("^[\(arrangement.proposals.count) piece](inflect: true)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Paper.secondaryInk)
                                }
                                .frame(width: 124, height: 74, alignment: .topLeading)
                                .padding(10)
                                .paperCard(radius: 14)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { forget(arrangement) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Editing

    private var suggestedName: String { "Layout \(room.arrangements.count + 1)" }

    /// Snapshot the arrangement *before* it changes, so one gesture is one undo step.
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

    private func apply(_ proposals: [Proposal]) {
        room.proposals = proposals
        if let selection, !proposals.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    private func clearAll() {
        checkpoint()
        room.proposals = []
        selection = nil
    }

    private func keepArrangement() {
        let name = arrangementName.trimmingCharacters(in: .whitespaces)
        room.arrangements = room.arrangements
            + [Arrangement(name: name.isEmpty ? suggestedName : name, proposals: room.proposals)]
    }

    private func restore(_ arrangement: Arrangement) {
        checkpoint()
        apply(arrangement.proposals)
    }

    private func forget(_ arrangement: Arrangement) {
        room.arrangements = room.arrangements.filter { $0.id != arrangement.id }
    }

    /// New pieces land in the middle of the room, stepped aside a little each
    /// time so two added in a row do not sit exactly on top of each other.
    private func add(_ kind: Furniture.Kind, linking product: UUID? = nil) {
        guard let captured = room.capturedRoom else { return }
        let bounds = RoomGeometry.build(from: captured).bounds
        let step = Float(room.proposals.count % 5) * 0.35
        let spot = Camera.clamp(Camera.centre(of: bounds) + SIMD2(step, step), in: bounds)
        checkpoint()
        var proposal = Proposal(kind: kind, position: spot)
        proposal.libraryObjectID = product
        room.proposals = room.proposals + [proposal]
        selection = proposal.id
    }

    private func add(_ object: LibraryObject) {
        guard let kind = object.furnitureKind else { return }
        add(kind, linking: object.id)
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
    }

    private func mutate(_ proposal: Proposal, _ change: (inout Proposal) -> Void) {
        checkpoint()
        guard let index = room.proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        var updated = room.proposals
        change(&updated[index])
        room.proposals = updated
    }
}
