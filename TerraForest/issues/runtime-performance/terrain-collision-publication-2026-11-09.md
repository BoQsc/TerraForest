# Terrain collision publication — 2026-11-09

Status: cold attachment cost reproduced; production change not selected.
This extends [native world attribution](native-world-process-2026-11-09.md),
which retained a 2.182 ms terrain collision-node attachment in a real-world
frame. That operation is outside the block-world callback.

## What the previous timer missed

`NativeTerrainCollisionPiece.resolve()` creates a Godot shape and assigns its
faces. Its legacy `cook_ms` field measures that resource setup. The earlier
`terrain_collision` benchmark explicitly excludes node attachment and simulation.
It cannot establish the complete collision-publication cost.

In pinned Godot `ed1daf0bf`, parenting a `CollisionShape3D` registers its shape
with its body. For a live Jolt body, the shape change commits the body shape,
including previously unbuilt concave geometry and compound construction.
Deferring a body outside the physics space postpones this work until admission.
[CollisionShape3D registration](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/scene/3d/physics/collision_shape_3d.cpp),
[Jolt shape commit](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/modules/jolt_physics/objects/jolt_shaped_object_3d.cpp),
[concave mesh construction](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/modules/jolt_physics/shapes/jolt_concave_polygon_shape_3d.cpp).
This code path supports a cold-construction cause; it does not identify every
world hitch or imply that GDScript-to-C++ conversion alone removes the cost.

## Actual-body diagnostic

`tests/terrain_collision.gd --profile-attachment` now compares newly created
shapes on a live body, shapes reused from another live body, and cold shapes on
a body admitted only after all pieces are attached. All bodies use layer/mask
zero as production preparation does. The final deferred admission is explicitly
included as an indivisible unit; its cost is not hidden by the cheaper earlier
attachments. The diagnostic is original project code; no engine implementation
is copied or distributed.

The [run](../../reports/checks/20261109T193558625910Z_terrain_attachment/run.json)
passes 144 checks with no error/leak diagnostics. It uses one 2,356-triangle
native terrain patch, six iterations per partition size and Jolt Physics.
Every partition reassembles exactly the original ordered triangles, every body
owns all expected shapes in a real physics space, and reuse counts are checked.
Bodies are freed after each iteration. No simulation, rendering, movement,
retirement timing or long-session memory acceptance is claimed.

| Triangles per piece / pieces | Cold live total / largest unit ms | Reused live total ms | Cold deferred total / final admission ms |
| --- | --- | --- | --- |
| 256 / 10 | 1.704 / 0.286 | 0.128 | 1.580 / 1.371 |
| 512 / 5 | 1.523 / 0.363 | 0.092 | 1.460 / 1.287 |
| 1024 / 3 (current default) | 1.464 / 0.643 | 0.072 | 1.412 / 1.250 |

These are the fixture's six-sample median summaries. For 1024-triangle pieces,
cold resource setup is 0.086 ms and attachment 1.358 ms; live-reused attachment
is 0.029 ms. Most cold work therefore happens after the earlier setup timer.
Splitting reduces the largest measured unit but raises total work. Deferring
the whole body makes its final unit larger than incremental live attachment.

The user's interactive reload playtest (PID 47308) was already running; the
process inventory is retained. This is a contended microbenchmark, not an
uncontended performance baseline, whole-frame saving, or percentile guarantee.
Repeat controlled tests before using the values to choose a production default.
[Exact timings and identities](terrain-collision-publication-2026-11-09.json).

## Next gate

Use the existing pre-worker `configure_collision_piece_size()` diagnostic
configuration to compare the current 1024 limit with smaller bounded pieces
in the retained default-world fixture. Keep full triangle coverage and measure
total publication latency, shape counts, memory, frame tails and simulation
cost. Preserve atomic mesh/collision readiness, cancellation and edit recovery.
Run real walking, slopes, mining and collision-boundary checks: identical
triangles alone do not prove equivalent contact behavior at new piece boundaries.
Only adopt a size/publication change after these checks and controlled frame
comparisons pass. The current default and production scheduling are unchanged.
Rendering, player/actor physics, explosions, pursuit and endurance remain open.
