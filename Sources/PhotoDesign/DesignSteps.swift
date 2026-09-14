import SwiftUI
import simd

// MARK: - Where

/// Photo spots first: a picture comes out best from a spot that was photographed.
struct WhereStep: View {
    let room: ScannedRoom
    @ObservedObject var draft: DesignDraft
    let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
    let onNext: () -> Void

    @Environment(\.roomAccent) private var accent
    /// Built once for this step and kept: renderer, mesh and measured bounds.
    @StateObject private var inside = InsideRenderer()
    @State private var isAiming = false
    @State private var isAdjusting = false
    @ObservedObject private var learned = Learned.shared

    private var photos: [ScanPhoto] { room.sortedPhotos }

    /// The photographed spots are the only part of Design nobody would guess.
    /// With no photos there is nothing to explain, so nothing is said.
    private var isTeaching: Bool { !learned.hasSeen(.designWhere) && !photos.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where are you\nstanding?").question()
                        Text(photos.isEmpty
                             ? "No photos were taken while this room was scanned, so the picture is drawn from the scan alone."
                             : "Pictures come out best from a spot you photographed while scanning.")
                            .font(.system(size: 14))
                            .foregroundStyle(Paper.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                    if !photos.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)], spacing: 14) {
                            ForEach(photos.indices, id: \.self) { spot($0) }
                        }
                        .padding(.horizontal, 20)
                    }

                    anyAngle
                        .padding(.horizontal, 20)
                        .padding(.top, photos.isEmpty ? 0 : 18)

                    if draft.angle == .free {
                        InsideView(image: inside.image)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                        Text("Lens \(Lens.degrees(draft.freeFieldOfView))° — \(Lens.shot.words(draft.freeFieldOfView)).")
                            .font(.system(size: 13))
                            .foregroundStyle(Paper.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        Button { isAdjusting = true } label: {
                            Label("Move the camera", systemImage: "move.3d")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }
                }
                .padding(.bottom, 16)
            }

            Button("Next", action: onNext)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
        }
        .overlay(alignment: .bottom) { lesson }
        // Driven from here rather than from the plan: the plan publishes where
        // the camera is, never when the picture of it is out of date. It stays
        // here now that the plan is on a sheet, so the frame behind the sheet
        // is already right when the sheet closes.
        .task { await buildMesh() }
        .onChange(of: draft.angle) { redraw() }
        .onChange(of: draft.freePosition) { redraw(rough: isAiming) }
        .onChange(of: draft.freeYaw) { redraw(rough: isAiming) }
        .onChange(of: draft.freePitch) { redraw(rough: isAiming) }
        .onChange(of: draft.freeEyeHeight) { redraw(rough: isAiming) }
        .onChange(of: draft.freeFieldOfView) { redraw(rough: isAiming) }
        .onChange(of: isAiming) { if !isAiming { redraw() } }
        .onChange(of: room.proposalsData) { Task { await rebuildMesh() } }
        .sheet(isPresented: $isAdjusting) {
            if let plan {
                AnyAngleSheet(room: room, plan: plan, draft: draft,
                              inside: inside, isAiming: $isAiming)
            }
        }
    }

    /// Sits under the photos rather than over them: a card must never cover the
    /// thing it is describing.
    @ViewBuilder private var lesson: some View {
        if isTeaching {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.46)
                    .ignoresSafeArea()
                    .onTapGesture { learned.mark(.designWhere) }
                LearnCard(
                    title: "Stand where you stood",
                    lines: ["While you were scanning, the app kept a photo at each of these spots and remembered exactly where you were standing. Choose one and the picture is made from there, so it lines up with the room you already know.",
                            "Any angle works too. It just has no photograph to match."],
                    onDismiss: { learned.mark(.designWhere) })
                    .padding(.bottom, 26)
            }
            .transition(.opacity)
        }
    }

    /// The one mesh this step renders from, assembled off the main thread and
    /// then kept — never rebuilt for a frame.
    private func buildMesh() async {
        guard !inside.isLoaded, let captured = room.capturedRoom else { return }
        let proposals = room.proposals
        let built = await Task.detached(priority: .userInitiated) { () -> (Mesh, RoomFloor?) in
            (RoomGeometry.build(from: captured, proposals: proposals), RoomFloor(room: captured))
        }.value
        inside.load(built.0)
        standInside(built.1)
        redraw()
    }

    /// Rebuilt only when the furniture changes, which now it can: a piece added
    /// on the mini screen has to appear in the frame it will appear in.
    private func rebuildMesh() async {
        guard let captured = room.capturedRoom else { return }
        let proposals = room.proposals
        let built = await Task.detached(priority: .userInitiated) {
            RoomGeometry.build(from: captured, proposals: proposals)
        }.value
        inside.load(built)
        redraw()
    }

    /// The bounding box is not the room: a room scanned at an angle has box
    /// corners outside its own walls, and opening in one fills the frame with
    /// the back of a wall. The floor polygon is what says "room".
    private func standInside(_ floor: RoomFloor?) {
        guard let floor else { return }
        // Pushed back to the nearest spot inside, which keeps the opening corner
        // a corner: the middle of a room facing level is a bare wall.
        let inside = floor.keepInside(draft.freePosition, margin: 0.4)
        guard inside != draft.freePosition else { return }
        draft.freePosition = inside
        draft.freeYaw = floor.heading(from: inside)
    }

    /// Rough while a finger is down, sharp once it lifts. Requests supersede
    /// rather than queue, so a fast drag never renders a position already left.
    private func redraw(rough: Bool = false) {
        guard draft.angle == .free else { return }
        inside.request(position: draft.freePosition, yaw: draft.freeYaw,
                       pitch: draft.freePitch, eyeHeight: draft.freeEyeHeight,
                       fieldOfView: draft.freeFieldOfView, draft: rough)
    }

    private var plan: FloorPlan? { room.capturedRoom.map { FloorPlan(room: $0) } }

    private func spot(_ index: Int) -> some View {
        let selected = draft.angle == .photo(index)
        return Button { draft.angle = .photo(index) } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    FilledImage(image: photos[index].thumbnail)
                    .frame(height: 186)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(selected ? accent : .clear, lineWidth: 3)
                    }

                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(selected ? accent : Color.black.opacity(0.55), in: Circle())
                        .padding(9)
                }
                Text("Photo \(index + 1)")
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Paper.ink)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Choosing it opens the mini screen: with no photographed spot to fall back
    /// on, a dot on a small plan was all you got, and it was not enough to aim
    /// a picture with.
    private var anyAngle: some View {
        let selected = draft.angle == .free
        return Button {
            draft.angle = .free
            isAdjusting = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "move.3d")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Paper.mutedInk)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Any angle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                    Text("Move the camera yourself, and widen the lens. Less true to life.")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 76)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? accent : .clear, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The room from where you are standing, cropped to the frame the picture is
/// cut from — so aiming is done by looking rather than by reading a map.
private struct InsideView: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            Paper.tint
            if let image {
                // Already cropped to the 4:3 `freeShot` cuts the picture from,
                // so nothing on screen lies outside the picture.
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                ProgressView().tint(Paper.mutedInk)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Paper.outline, lineWidth: 1)
        }
        .accessibilityLabel("The room seen from where you are standing")
    }
}

/// "Any angle", as a screen you can work in rather than a dot on a map.
///
/// A sheet rather than a push or a screen of its own: it answers one step's
/// question, the step stays behind it, and Done puts you back on it with the
/// frame already redrawn. What it holds is the three things that decide the
/// picture — what the camera sees, where it stands, and how wide it looks — and
/// the furniture, because the plan is one instrument everywhere it appears.
private struct AnyAngleSheet: View {
    let room: ScannedRoom
    let plan: FloorPlan
    @ObservedObject var draft: DesignDraft
    @ObservedObject var inside: InsideRenderer
    @Binding var isAiming: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Paper.sheet.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Already cropped to the 4:3 the picture is cut to, so
                        // nothing you aim at lies outside it.
                        ViewfinderView(image: inside.image, yaw: $draft.freeYaw,
                                       pitch: $draft.freePitch, isDragging: $isAiming)
                            .aspectRatio(4.0 / 3.0, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        Text("Exactly the frame the picture is cut from. Drag it to turn and tilt.")
                            .font(.system(size: 13))
                            .foregroundStyle(Paper.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

                        PlanBoard(room: room, plan: plan,
                                  position: $draft.freePosition, yaw: $draft.freeYaw,
                                  fieldOfView: $draft.freeFieldOfView, isDragging: $isAiming,
                                  eyeHeight: $draft.freeEyeHeight,
                                  lens: .shot, planHeight: 240,
                                  photoSpots: room.sortedPhotos.map(\.planSpot))
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 28)
                    }
                }
            }
            .navigationTitle("Any angle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - What

/// What goes in the room: what is already on the plan, plus anything with no spot.
struct WhatStep: View {
    @ObservedObject var draft: DesignDraft
    let placed: [PlacedProduct]
    let library: [LibraryObject]
    @ObservedObject var thumbnails: ProductThumbnails
    let onNext: () -> Void

    @State private var isAddingUnplaced = false

    private var onPlan: [PlacedProduct] { placed.filter { $0.marker != nil } }
    private var leftOut: [PlacedProduct] { placed.filter { $0.marker == nil } }
    private var unplaced: [LibraryObject] {
        draft.unplacedIDs.compactMap { id in library.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's going\nin the room?").question()
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(Paper.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                    VStack(spacing: 10) {
                        ForEach(onPlan) { product in
                            placedRow(product)
                        }
                        ForEach(unplaced) { object in
                            unplacedRow(object)
                        }
                        somethingElse
                    }
                    .padding(.horizontal, 20)

                    if !leftOut.isEmpty {
                        Text("One picture takes at most \(PhotoDesignScene.maxProducts) products, so these are left out: \(leftOut.map(\.object.name).joined(separator: ", ")).")
                            .font(.system(size: 13))
                            .foregroundStyle(Paper.secondaryInk)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    nothingNew
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                }
                .padding(.bottom, 16)
            }

            Button("Next", action: onNext)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
        }
        .sheet(isPresented: $isAddingUnplaced) {
            LibraryPicker(
                title: "Add without placing",
                footnote: "For things with no spot on the floor plan, like a painting, a mirror or curtains. The picture puts them wherever your prompt says, so say where: \"hang the painting above the sofa\".",
                unavailable: { object in
                    if draft.unplacedIDs.contains(object.id) { return "Already in the picture" }
                    if placed.contains(where: { $0.object.id == object.id }) { return "Already placed on the floor plan" }
                    return nil
                },
                onPick: { draft.unplacedIDs = draft.unplacedIDs + [$0.id] })
        }
    }

    private var subtitle: String {
        if onPlan.isEmpty {
            return "Nothing is standing on your plan yet. Add something with no spot of its own, or restyle the room as it is."
        }
        if onPlan.count == 1 {
            return "One is already standing on your plan. Its colour is how the picture knows where it goes."
        }
        return "\(onPlan.count) are already standing on your plan. Their colour is how the picture knows where they go."
    }

    private var chosenCount: Int {
        onPlan.filter { !draft.excluded.contains($0.proposal.id) }.count + unplaced.count
    }

    private func placedRow(_ product: PlacedProduct) -> some View {
        let isOn = !draft.excluded.contains(product.proposal.id)
        let tint = product.marker?.color ?? Paper.outline
        return Button {
            if isOn { draft.excluded.insert(product.proposal.id) }
            else { draft.excluded.remove(product.proposal.id) }
        } label: {
            row(thumbnail: thumbnails.images[product.object.id],
                name: product.object.name,
                marker: product.marker,
                note: "On the plan") {
                Image(systemName: isOn ? "checkmark" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOn ? tint : Paper.outline)
                    .frame(width: 24, height: 24)
            }
            .paperCard()
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOn ? tint : .clear, lineWidth: 2)
            }
            .opacity(isOn ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(product.object.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func unplacedRow(_ object: LibraryObject) -> some View {
        row(thumbnail: thumbnails.images[object.id],
            name: object.name,
            marker: nil,
            note: "Not placed. It goes wherever your prompt says.") {
            Button {
                draft.unplacedIDs = draft.unplacedIDs.filter { $0 != object.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Paper.mutedInk)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(object.name)")
        }
        .paperCard()
    }

    private var somethingElse: some View {
        Button { isAddingUnplaced = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Paper.deepTint)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Paper.mutedInk)
                }
                .frame(width: 92, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Something else")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                    Text("A painting, curtains — no spot needed")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 96)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(chosenCount >= PhotoDesignScene.maxProducts)
    }

    /// The same compose call with no products at all.
    private var nothingNew: some View {
        Button {
            draft.excluded = Set(onPlan.map(\.proposal.id))
            draft.unplacedIDs = []
            onNext()
        } label: {
            Text("Nothing new — just restyle the room")
                .font(.system(size: 15))
                .foregroundStyle(Paper.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 62)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Paper.outline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
        }
        .buttonStyle(.plain)
    }

    private func row<Trailing: View>(thumbnail: UIImage?, name: String, marker: Marker?,
                                     note: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            FilledImage(image: thumbnail, symbol: "photo")
                .frame(width: 92, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    MarkerDot(marker: marker)
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 96)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - How

/// How it should feel, and the one button that makes the picture.
struct HowStep: View {
    let room: ScannedRoom
    @ObservedObject var draft: DesignDraft
    let chosen: [PlacedProduct]
    let unplaced: [LibraryObject]
    let sourcePhoto: ScanPhoto?
    @ObservedObject var run: PhotoDesignRun
    let onMake: () -> Void

    @Environment(\.roomAccent) private var accent
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("How should it\nfeel?").question()
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 18)

                    TextField("Warm and cosy for winter evenings",
                              text: $draft.prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .tracking(-0.18)
                        .foregroundStyle(Paper.ink)
                        .lineLimit(3...8)
                        .focused($isEditing)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .frame(minHeight: 116, alignment: .top)
                        .paperCard()
                        .padding(.horizontal, 20)

                    SuggestionIdeas(text: $draft.prompt, room: room)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    speed
                        .padding(.horizontal, 20)
                        .padding(.top, 26)
                }
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 10) {
                if run.isWorking { progress } else { summary }
                Button(action: onMake) {
                    Text(run.isWorking ? "Working…" : "Make the picture")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(draft.trimmedPrompt.isEmpty || run.isWorking)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
    }

    private var speed: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(PhotoDesignModel.allCases) { model in
                    let on = draft.model == model
                    Button { draft.model = model } label: {
                        Text(model.shortName)
                            .font(.system(size: 15, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Paper.ink : Paper.secondaryInk)
                            .frame(height: 44)
                            .padding(.horizontal, 18)
                            .background {
                                if on {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Paper.card)
                                        .shadow(color: Paper.cardShadow, radius: 1.5, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Paper.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(draft.model.costNote)
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            if let image = sourcePhoto?.thumbnail {
                FilledImage(image: image)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 5) {
                ForEach(chosen) { product in
                    MarkerDot(marker: product.marker, size: 9)
                }
            }
            Text(summaryText)
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var summaryText: String {
        let where_: String
        if case .photo(let index) = draft.angle { where_ = "Photo \(index + 1)" } else { where_ = "Any angle" }
        let count = chosen.count + unplaced.count
        let what = count == 0 ? "just the room" : (count == 1 ? "1 product" : "\(count) products")
        return "\(where_) · \(what)"
    }

    @ViewBuilder private var progress: some View {
        HStack(spacing: 10) {
            ProgressView().tint(accent)
            Text(progressText)
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var progressText: String {
        switch run.stage {
        case .uploading(let done, let total): return "Sending the pictures… \(done) of \(total)"
        case .designing: return draft.model.waitingNote
        case .downloading: return "Fetching the picture…"
        default: return ""
        }
    }
}
