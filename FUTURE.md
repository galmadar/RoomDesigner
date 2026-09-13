# Future

Problems we have found and not fixed, written down properly so they are not lost.

An entry lands here when something is found, not when it is scheduled. Nothing
here is a commitment, an estimate, or a plan of record; it is a description of
what is wrong and what it would take to put right.

## Correcting what a room is

A guest room with two tables and a sofa is treated as a kitchen. Nothing in the
app says "kitchen" out loud, but the design ideas offered for it are kitchen
ideas.

The room type is not a field anyone set. `RoomFacts.kind(from:)`
(`Sources/Network/RoomFacts.swift:85`) reads it off the set of object categories
the scan found: a `bed` makes it a bedroom, a `toilet` or `bathtub` a bathroom,
and any of `stove`, `oven`, `dishwasher` or `refrigerator` a kitchen — tested
before `sofa`, so one misclassified object outvotes the furniture that is
actually there. RoomPlan has no room-type field, so the inference is ours.

Its reach is narrow but real. `kind` is set in `RoomFacts.init` (line 23) and
goes only into the `/suggest` request (`PlanService.suggestions`,
`Sources/Network/PlanService.swift:52`), asked for from
`SuggestionIdeas.loadSuggestions` (`Sources/App/SuggestionIdeas.swift:71`).
Nothing else reads it — not the render, not the compose call. But the
suggestions come back as chips that the user taps to fill the brief, and the
brief is what the image model is told, so a wrong room type reaches the picture
by way of the person using the app.

Fixing it means letting the user say what the room is and storing that on
`ScannedRoom`, with today's inference as the fallback when they have not said.
That is a stored property, a place to set it (the room screen is the obvious
one), and `RoomFacts` preferring it over the guess. Small: one field, one
control, one branch.

## Correcting what a scanned object is

A closet is labelled "Fridge" on the floor plan and described to the suggestion
service as a "refrigerator". There is no way to tell the app otherwise.

The category is RoomPlan's, decided during the scan's post-processing pass, and
it arrives already fixed on `CapturedRoom.Object.category`. The app only ever
translates it: `FloorPlan.name(of:)`
(`Sources/FloorPlan/FloorPlan.swift:73`) for the plan's labels, and
`RoomFacts.name(of:)` (`Sources/Network/RoomFacts.swift:60`) for the service.
The scan itself is written exactly once, at `Sources/App/RoomListView.swift:59`,
when a capture finishes; every other use of `capturedRoom` reads. No screen
offers any edit of a scanned object.

Rescanning is not a fix and should not be offered as one. The same closet, the
same shape, in the same place, goes through the same classifier and will almost
certainly come back a refrigerator again.

Fixing it means storing a per-object override on the room — keyed by the
object's identifier — and consulting it everywhere a category is read today:
the plan's labels, the facts sent to the service, and `ProxyMeshLibrary`'s
lookup key (`Sources/Geometry/ProxyMeshLibrary.swift:44`), which is keyed on
category and would otherwise pick a proxy for the wrong thing. Medium: the
storage is easy, the work is that "what kind of thing is this" is currently
answered independently in three places.

## Correcting a scanned object's size and position

This is the more damaging half. RoomPlan gave the same closet a box roughly half
its real width. A wrong label is a wrong word; a wrong box is wrong geometry,
and the geometry is what the picture is built on.

Every scanned object becomes a box in the mesh:
`RoomGeometry.build` (`Sources/Geometry/RoomGeometry.swift:43`) asks
`ProxyMeshLibrary.mesh(for:)` for each one, which builds a cuboid from
`object.dimensions` and places it with `object.transform`
(`Sources/Geometry/ProxyMeshLibrary.swift:44`). That mesh is what goes to the
image model: `DesignFlowView.make()`
(`Sources/PhotoDesign/DesignFlowView.swift:153`) builds it, renders it through
`ShotRenderer`, and `PhotoDesignRun` uploads the PNG
(`Sources/PhotoDesign/PhotoDesignRun.swift:73`) and names it as `scan_url` in
the compose request (line 91). The same mesh is also what you walk through
(`Sources/Walk/WalkState.swift:55`) and the footprints drawn on the plan
(`Sources/FloorPlan/FloorPlan.swift:32`). So a half-width closet is half-width
in every generated picture of that wall, and no prompt can argue with it.

The editing gestures already exist. `LayoutView` lets you drag a piece, and its
controls turn, resize and remove it (`Sources/FloorPlan/LayoutView.swift:310`
onwards) — but every one of those mutates `room.proposals`, the furniture the
user placed. Scanned objects are not in that array, are not selectable, and have
nowhere for an edit to be written.

Fixing it means an overlay of corrections stored on the room — a size and a
transform per scanned object, keyed by object identifier — applied wherever the
scan is turned into something: the mesh, the plan, the facts. The plan view
would need scanned footprints to be selectable, which today they are not, and
the existing turn/resize/remove controls would then need to act on whichever
kind of thing is selected.

One design question has to be answered before any of it: does an edited scan
stay edited if the room is ever rescanned? A rescan produces new objects with
new identifiers, so corrections cannot simply be carried over, and silently
dropping them would lose work the user did by hand. Either a rescan replaces the
room outright and says so, or corrections have to be matched to the new objects
by position, which is its own guess. The biggest item on this list.

## Room area is wrong for rooms that are not square to the world

A room card says a room is about 18.8 m² when it measures about 9.5 m².

`FloorPlan.floorAreaSquareMetres` (`Sources/FloorPlan/FloorPlan.swift:50`) is
documented as "shoelace over the wall endpoints" and does not do that: it takes
`bounds.max - bounds.min` and multiplies, which is the area of the axis-aligned
bounding box of the wall endpoints. For a room square to the world axes the two
agree. For a room scanned at an angle, or an L-shaped one, the box is larger
than the floor, and for a room turned 45° it is close to twice as large.

It is shown on every room card in the list
(`Sources/App/RoomListView.swift:197`). The same `bounds` also produce the
`width` and `length` sent to the suggestion service
(`Sources/Network/RoomFacts.swift:28`), so an angled room is described to the
service as bigger than it is as well.

The fix is a shoelace sum over the floor's own outline rather than the wall
endpoints' bounding box. The outline is already available — RoomPlan gives
`polygonCorners` on the floor surface, and `RoomGeometry.polygon(of:)`
(`Sources/Geometry/RoomGeometry.swift:133`) already extracts it with a
rectangular fallback — so this is a handful of lines plus deciding what to show
for a scan with no floor surface at all. Small.

## Windows render as black holes

Walking through a scanned room, a window is a void: a dark rectangle in the wall
with nothing beyond it, which reads less like a window than like a hole knocked
through into empty space.

Apertures are subtracted, not filled. Windows, doors and openings arrive from
RoomPlan as their own surfaces rather than as holes, so `RoomGeometry.surface`
(`Sources/Geometry/RoomGeometry.swift:99`) cuts their rectangles out of the
parent wall by slab decomposition, and nothing is ever put back. There is no
glass, no frame and no backdrop behind them: the mesh contains walls, floors, a
built ceiling, scanned objects and proposed furniture, and that is all. What
shows through is the clear colour — 0.05, 0.05, 0.06 in both the offscreen pass
(`Sources/Rendering/Renderer.swift:87`) and the live walk
(`Sources/Rendering/WalkRenderer.swift:77`).

It is not only how it looks. In the conditioning renders the depth attachment is
cleared to "infinitely far" (`Sources/Rendering/Renderer.swift:81`), so a window
is a region of no geometry at all — which is exactly what the app tells the
image model an empty doorway or a missing wall looks like.

Fixing it is a choice rather than a puzzle: a pane surface across each aperture,
or a plane at some distance behind the wall standing in for outside. Either is a
small addition to the mesh. The real work is deciding what a window should mean
to the model — a bright surface it can put daylight through, or a far-away
something it can put a view on — and that is worth testing rather than arguing
about. Small to medium.

## The free camera is kept inside the bounding box, not inside the room

Found while checking the above, and the same root cause as the area bug.

Choosing "any angle" in the design flow stands a camera at a spot you pick on
the plan. That spot is clamped with `Camera.clamp`
(`Sources/Rendering/Camera.swift:29`), which holds it inside the mesh's
axis-aligned bounding box — both when the flow first places you in a corner
(`Sources/PhotoDesign/DesignFlowView.swift:214`) and when the camera is built
each time (line 100). In a room scanned at an angle the bounding box overhangs
the floor, so the camera can end up outside the walls, looking at the back of
the room; the render made from there is uploaded as `scan_url` and is what the
model is conditioned on.

The test for this already exists and is never called:
`PhotoDesignScene.isOnFloor(_:of:)`
(`Sources/PhotoDesign/PhotoDesignScene.swift:71`) tests a point against the
floor polygon and has no callers anywhere in the app. The walk screen solves the
same problem properly, with `RoomFloor.keepInside`
(`Sources/Walk/WalkState.swift:132`), and even says why in a comment: a room
scanned at an angle has box corners outside its own walls.

Fixing it means holding the free camera inside the floor polygon the way the
walk does, or wiring up `isOnFloor` to refuse a spot that is not in the room.
Small, and mostly a matter of choosing which of the two existing pieces of code
to use.
