# Roomsmith

An iPhone app that scans a room with LiDAR and gives back a photorealistic image
of that room redesigned — with its real walls, its real window, its real
proportions — plus a to-scale floor plan.

Not a generic pretty bedroom that happens to be the right shape. Yours.

## How it works

```
RoomPlan scan
  → CapturedRoom: walls, doors, windows and furniture, as measurements
  → a mesh, assembled from those structs (no USDZ round trip)
  → an offscreen Metal pass: depth, normals and edges in one draw
  → the depth map is the conditioning image
  → a small service holds the API key and calls a depth-ControlNet model
  → the picture comes back holding your geometry
```

The interesting constraint: conditioning on depth means the generator can only
furnish where geometry already exists. An empty wall stays an empty wall however
the prompt is worded. So the app lets you **place proposed furniture into the
mesh before it renders** — the model cannot tell a scanned sofa from an imagined
one, which is what makes it a redesigner rather than a restyler.

## Notes on a few decisions

**Geometry is built from `CapturedRoom` directly**, not from the USDZ export.
Everything needed is already in memory as parametric structs, and building it
ourselves is what makes proposed furniture possible at all. Windows and doors
arrive as separate surfaces rather than holes, so they are subtracted from their
parent wall by slab decomposition.

**Rendering is Metal, not RealityKit.** `RealityRenderer` is genuinely headless,
but its `CameraOutput` exposes only colour textures with no way to bind a depth
attachment — and depth is the whole point. A plain render pass yields depth,
normals, a flat render and a line drawing from one draw.

**Furniture proxies are procedural.** RoomPlan describes every object as a
bounding box — in Apple's words, it *"approximates the size and shape of objects
it observes in a scan by using bounding boxes"* — so a sofa is a cuboid and the
category is a label on a box. Proposed pieces are assembled from primitives
instead: a sofa is a base, a back and two arms. They only ever become a depth map
or a silhouette, so proportion and surface orientation are what matter, not
likeness. No assets, no licensing.

**SceneKit is not used.** It is formally deprecated as of iOS 26.

**A demo room ships with the app.** Scanning needs LiDAR, which only Pro iPhones
have, and the App Store cannot be told to hide the app from the rest:
[Required Device Capabilities](https://developer.apple.com/support/required-device-capabilities/)
has no value for a depth sensor, and the nearest one, `arkit`, means only "an
A9 or later processor" — which every iPhone that can run iOS 17 already is. So
the app says what the phone cannot do and offers something to look at instead:
`Sources/Demo/DemoRoom.json` is a hand-written `CapturedRoom` — a rectangular
4.4 m by 3.6 m living room with a window, a door and five pieces of furniture,
every measurement typed rather than measured. It can be walked through, seen on
the plan and taken through the design flow; nothing that costs money is offered
for it. No real scan ever ships.

## Building it

Requires Xcode 26+, an iPhone with a **LiDAR scanner** (a Pro model), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cp Local.xcconfig.example Local.xcconfig   # then put your Apple team ID in it
xcodegen generate
open Roomsmith.xcodeproj
```

Scanning, the floor plan and the viewpoint preview all work with nothing else
set up. Generating a redesign needs the companion service running and its
address entered in the app's settings:
**[room-designer-server](https://github.com/galmadar/room-designer-server)**.

## Layout

| Path | |
|---|---|
| `Sources/Capture/` | RoomPlan scanning, bridged into SwiftUI |
| `Sources/Geometry/` | `CapturedRoom` → mesh, triangulation, furniture proxies |
| `Sources/Rendering/` | the Metal pass, the camera, conditioning images |
| `Sources/FloorPlan/` | the plan, which doubles as the viewpoint and furniture editor |
| `Sources/Demo/` | the bundled room for iPhones that cannot scan |
| `Sources/Model/` | SwiftData storage; everything stays on the device |
| `Sources/Network/` | the one call to the generation service |
