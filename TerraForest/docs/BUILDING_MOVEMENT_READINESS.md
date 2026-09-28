# Local building movement readiness

`NativeBlockWorld.is_collision_region_ready(world_bounds)` checks a positive,
finite world-space AABB. It transforms the bounds into block-world space and
checks occupied column masks only in intersecting authored chunks. Empty space
inside an unfinished chunk does not block movement. The query fails closed for
invalid or singular transforms and for intersecting authored cells whose mesh
or collision is dirty, pending, disabled, evicted or budget-deferred. Settled
fully enclosed chunks with no surface triangles require no body.

The query is read-only and native. It scans at most the authored chunk limit
(2,048), with bounded 16-by-16 column-mask checks per intersecting chunk. It
does not enumerate a huge caller-provided volume or create physics resources.
Partial shapes conservatively occupy their whole authored cell for this gate.
Transformed bounds use a conservative enclosing AABB.

The main world's walking controller checks the region before `move_and_slide`.
Bounds include its capsule, floor-snap reach, a 0.05-metre margin, and the tick's
full travel distance in every direction to cover sliding. If the region is not
ready, velocity is zeroed and movement is skipped. Input remains current state,
so releasing keys while waiting cannot queue delayed movement. The next tick
rechecks readiness and resumes automatically when the region is ready. Removing
unavailable authored support also releases the gate because that space is empty.
The HUD reports waiting for building collision.

The base terrain controller exposes an additional-motion hook; the main world
uses it to call the native structures query. Existing terrain readiness remains
in force. The controller itself is still the inherited GDScript implementation;
this does not complete the requested native player redesign. Editor flight stays
free-moving and bypasses the walking gate.

## Scope and remaining work

This gate covers block buildings only. Static model collision, vehicles,
multiplayer movement authority, prediction and arbitrary teleport safety remain
separate work. A region that cannot fit configured streaming budgets can remain
blocked until the caller changes the budget or authored data. There is no timeout
that silently allows traversal through missing collision. Collider cooking and
mesh publication can still stall despite movement waiting correctly.

## Verified scope

Debug and clean release builds each pass 15 native checks covering empty regions,
invalid bounds, negative coordinates, empty space within an unfinished chunk,
touching faces, disabled/complete/dirty/evicted collision, world transforms,
singular transforms, chunk-budget deferral and deletion of unavailable support.

The integrated main-world test passes 154 checks at 1920x1080 fullscreen. Six
new checks verify terrain readiness independently, hold the actual walking
controller above an unavailable authored platform with a movement key held,
resume automatically after admission, land on the correct surface, hold when
collision is lost underfoot, and release into empty space after support removal.
This is a short correctness test, not a high-speed or long-run guarantee.

Reports and build hashes are retained in `evidence/building_readiness/`. Initial
build publication was blocked by open Godot processes holding the DLL. Identical
native sources were built in an isolated copy; after the editor/world closed,
both binaries were installed in the main project and the fullscreen test ran
there. Build reports retain the isolated output paths. No SDK sources rebuilt.
