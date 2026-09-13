# RoomDesigner

An iPhone app that scans a room with RoomPlan, turns the scan into a mesh, and
renders that mesh offscreen into the conditioning image an image model is asked
to redesign the room from. Because the picture is conditioned on real geometry,
furniture the user places on the floor plan is put into the same mesh before it
renders — the model cannot tell a scanned sofa from a proposed one. Everything
is stored on the device with SwiftData; a small companion service holds the API
keys and does the generating. `README.md` has the pipeline and the reasoning
behind the larger decisions.

[`FUTURE.md`](FUTURE.md) records problems that are known and not fixed — what
the user sees, why it happens, and what fixing it would involve. Read it before
concluding something is a new bug.

## Traps

**SwiftData does not observe in-place mutation of a stored array.** Assign a
fresh array instead of mutating one — `room.conceptImages = remaining`, not
`room.conceptImages.remove(at:)`. `LayoutView` writes the whole proposals array
back for this reason, and `ScannedRoom` stores proposals and arrangements as
encoded blobs rather than arrays to sidestep it entirely.

**The Xcode project is generated.** `RoomDesigner.xcodeproj/` is gitignored and
built by `xcodegen generate` from `project.yml`, which takes `Sources` as a
folder. New files under `Sources/` are picked up with no project edit; never
hand-edit the project file.

**`Local.xcconfig` holds signing and is gitignored.** Copy it from
`Local.xcconfig.example` and put your own team ID in it. Both Debug and Release
reference it, so the project will not build without it.

**Scanning cannot be tested in the simulator.** RoomPlan needs a LiDAR device;
the app checks `RoomCaptureSession.isSupported` and says so on the scan screen.
The rest — plan, layout, walk, design flow — works against an already-scanned
room, and `OPEN_ROOM` in the environment opens the app straight into one.

**The offscreen renders must not change.** They are what the image model is
conditioned on, so the render path has been changed only under proof that the
pixels did not move: the shared pipeline was extracted unchanged so the live
walk could not drift from the still it is drawn from (`a02e07c`), and
`ShotRenderer`'s camera path was checked pixel-identical, mean difference
0.00/255, against the path it replaced (`37d16ac`). Any change to `Renderer`,
`Shaders.metal`, `RoomPipeline` or `RoomGeometry` changes the picture the model
gets; hold it to the same standard.
