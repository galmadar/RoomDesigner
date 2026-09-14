import SwiftData
import SwiftUI
import simd

/// The plan and everything you can do from it, in one piece, used wherever a
/// plan appears.
///
/// There were three of these: a Layout screen that could arrange furniture but
/// had no camera, the design flow's picker that could aim a camera but not
/// touch the furniture, and the plan under "See the scan" that could do neither
/// properly. Three half-instruments meant learning the same plan three times
/// and finding out which half each screen had. This is all of it — stand
/// somewhere, turn, open the lens, and add, move, turn, resize or remove the
/// furniture standing on the floor — so what you learn on one screen is what
/// you already know on the other.
struct PlanBoard: View {
    let room: ScannedRoom
    let plan: FloorPlan

    @Binding var position: SIMD2<Float>
    @Binding var yaw: Float
    @Binding var fieldOfView: Float
    /// True while a finger is down, so the screen above can draw rough and
    /// sharpen on release.
    @Binding var isDragging: Bool

    /// Where the eye is, on the screens that let it move.
    var eyeHeight: Binding<Float>?

    /// Which frame the lens number describes; the bands differ per frame.
    var lens: Lens

    var planHeight: CGFloat = 260

    /// Where each photo was taken, in the room's photo order.
    var photoSpots: [PlanSpot?] = []
    var activeSpot: Int?
    var onPickSpot: (Int) -> Void = { _ in }

    @Environment(\.roomAccent) private var accent
    @Query(sort: \LibraryObject.createdAt, order: .reverse) private var library: [LibraryObject]
    @StateObject private var thumbnails = ProductThumbnails()

    @State private var selection: Proposal.ID?
    @State private var floor: RoomFloor?
    @State private var undoStack: [[Proposal]] = []
    @State private var redoStack: [[Proposal]] = []
    @State private var isPickingProduct = false
    @State private var isNamingArrangement = false
    @State private var arrangementName = ""

    /// The plan draws to the edge of whatever it is given; the writing beside it
    /// steps in, so a caller padding the board by 16 lands both where the app
    /// puts them.
    private let textInset: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CameraPlanPicker(plan: plan,
                             position: standing, yaw: $yaw,
                             isDragging: $isDragging, fieldOfView: $fieldOfView,
                             proposals: proposalsBinding, selection: $selection,
                             onBeginEdit: { checkpoint() },
                             links: planLinks,
                             canvas: Paper.tint,
                             photoSpots: photoSpots,
                             activeSpot: activeSpot,
                             onPickSpot: onPickSpot)
                .frame(height: planHeight)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text(hint)
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, textInset)
                .padding(.top, 10)

            // The camera's own two controls sit directly under the plan it
            // stands on, where the cone that widens is; the furniture's below
            // them.
            lensControl
                .padding(.horizontal, textInset)
                .padding(.top, 14)

            if let eyeHeight {
                heightControl(eyeHeight)
                    .padding(.horizontal, textInset)
                    .padding(.top, 12)
            }

            if let selected = selectedProposal {
                controls(selected)
                    .padding(.horizontal, textInset)
                    .padding(.top, 16)
            }

            tools
                .padding(.horizontal, textInset)
                .padding(.top, 12)

            saved
                .padding(.top, 16)
        }
        .task(id: library.map(\.id)) { await thumbnails.load(library) }
        .task { if floor == nil { floor = room.capturedRoom.flatMap { RoomFloor(room: $0) } } }
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

    /// The camera is held inside the floor's own outline, not inside the
    /// bounding box: a room scanned at an angle overhangs its box, and a spot
    /// out there looks at the back of a wall, which renders as a black frame.
    private var standing: Binding<SIMD2<Float>> {
        Binding(get: { position },
                set: { position = floor?.keepInside($0, margin: Self.wallMargin) ?? $0 })
    }

    private static let wallMargin: Float = 0.3

    private var hint: String {
        var said = ["Drag the dot to move, the small circle to turn. Pinch to zoom, drag the floor to move the map, double-tap to fit."]
        said.append(room.proposals.isEmpty
                    ? "Nothing on the plan yet — add a piece, then drag it into place."
                    : "Drag a piece to move it, tap it to turn, resize or remove.")
        if photoSpots.contains(where: { $0 != nil }) {
            said.append("Tap a numbered square to stand where that photo was taken.")
        }
        return said.joined(separator: " ")
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
            tile("rotate.left", "Turn left") { turn(selected, by: -.pi / 12) }
            tile("rotate.right", "Turn right") { turn(selected, by: .pi / 12) }
            tile("minus.magnifyingglass", "Smaller") { resize(selected, by: 0.9) }
            tile("plus.magnifyingglass", "Bigger") { resize(selected, by: 1.1) }
            tile("trash", "Remove", tint: Paper.destructive) { remove(selected) }
        }
    }

    /// Add, and the four things that act on the whole plan rather than on one
    /// piece. One row, always in the same place, on every screen the plan is on.
    private var tools: some View {
        HStack(spacing: 6) {
            Menu {
                Button { isPickingProduct = true } label: {
                    Label("From the library", systemImage: "square.grid.2x2")
                }
                Divider()
                ForEach(Furniture.Kind.allCases) { kind in
                    Button { add(kind) } label: { Label(kind.label, systemImage: kind.symbol) }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    Text("Add").font(.system(size: 16))
                }
                .fixedSize()
                .foregroundStyle(accent)
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(Paper.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("Add a piece")

            Spacer(minLength: 0)

            tile("arrow.uturn.backward", "Undo") { undo() }
                .disabled(undoStack.isEmpty)
            tile("arrow.uturn.forward", "Redo") { redo() }
                .disabled(redoStack.isEmpty)
            pill("Keep") {
                arrangementName = suggestedName
                isNamingArrangement = true
            }
            .disabled(room.proposals.isEmpty)
            pill("Clear", tint: Paper.destructive) { clearAll() }
                .disabled(room.proposals.isEmpty)
        }
    }

    private func tile(_ symbol: String, _ label: String, tint: Color = Paper.quietInk,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Paper.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func pill(_ title: String, tint: Color = Paper.quietInk,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(Paper.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var saved: some View {
        if !room.arrangements.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved versions")
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .padding(.horizontal, textInset)
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
                    .padding(.horizontal, textInset)
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - The lens and the eye

    private var lensControl: some View {
        slider(symbol: "arrow.left.and.right.square",
               value: Binding(get: { Double(fieldOfView) },
                              set: { fieldOfView = lens.clamped(Float($0)) }),
               range: Double(lens.range.lowerBound)...Double(lens.range.upperBound),
               label: "Lens \(Lens.degrees(fieldOfView))° — \(lens.words(fieldOfView))")
    }

    private func heightControl(_ metres: Binding<Float>) -> some View {
        slider(symbol: "figure.stand",
               value: Binding(get: { Double(metres.wrappedValue) },
                              set: { metres.wrappedValue = Float($0) }),
               range: 0.4...2.2,
               label: String(format: "Eye height %.2f m — %@", metres.wrappedValue,
                             Self.heightWords(metres.wrappedValue)))
    }

    private func slider(symbol: String, value: Binding<Double>,
                        range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Paper.mutedInk)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: value, in: range)
                    .frame(minHeight: 44)
                    .accessibilityLabel(label)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func heightWords(_ metres: Float) -> String {
        if metres < 0.8 { return "low, like sitting on the floor" }
        if metres < 1.3 { return "seated" }
        if metres < 1.8 { return "standing" }
        return "high, looking down into the room"
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

    /// Where a new piece may land: the plan's own walls, which is the only part
    /// of a bounds `Camera.centre` and `Camera.clamp` read. Taking it from the
    /// plan rather than from the mesh keeps the middle of the room the middle of
    /// the walls, and saves every screen having to hand its measurements in.
    private var placement: (min: SIMD3<Float>, max: SIMD3<Float>) {
        let (low, high) = plan.bounds
        return (SIMD3(low.x, 0, low.y), SIMD3(high.x, 0, high.y))
    }

    /// New pieces land in the middle of the room, stepped aside a little each
    /// time so two added in a row do not sit exactly on top of each other.
    private func add(_ kind: Furniture.Kind, linking product: UUID? = nil) {
        let bounds = placement
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
