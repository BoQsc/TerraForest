# Terrain collision publication — 2026-11-09

Status: cold attachment cost reproduced; smaller-piece production change rejected
after a four-run default-world comparison. Production remains at 1024 triangles.
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

## Default-world comparison and decision

The owned-world runner now accepts `--collision-piece-triangles 256|512|1024`.
It applies the existing backend setting before worker startup and requires that
configuration to succeed. The optional diagnostic retains bounded collision
attachment/publication/retirement samples, time to playable arrival, and a final
census of real resident collision nodes. The census joins every piece in body
order and hashes the original face bytes per terrain section, including bricks.
This expensive census runs after frame measurement. Normal gameplay is unchanged.
The added harness code is original project 0BSD code, with no imported material.

Four fresh copies of `StartupBench_FPS_20261109T073252` ran sequentially on source
`e7cc0956` plus the recorded diagnostic changes, in 1024/512/512/1024 order. The
normal browser, saved-world startup, same 16 m outdoor camera route, visuals,
normal save and graceful shutdown were retained. Rendering was uncapped at
1920×1080 on the RTX 4050 Laptop GPU. The rolling recorder was disabled in all
four runs; the collision-stage listener and root rendering timers were enabled
equally. Its overhead is not independently isolated. The camera sweep uses fly
mode, so it does not qualify grounded movement or terrain contacts.

| Run | Playable arrival s | Loading attachment median / p99 / max ms | Outdoor frame p99 / max ms | Resident shapes / triangles |
| --- | ---: | --- | --- | --- |
| 1024 A | 34.654 | 0.567 / 1.300 / 2.594 | 19.642 / 28.114 | 497 / 396,580 |
| 512 B | 35.214 | 0.320 / 0.671 / 1.346 | 23.262 / 31.629 | 1,041 / 440,676 |
| 512 B2 | 33.314 | 0.306 / 0.932 / 2.629 | 17.301 / 23.418 | 1,065 / 448,256 |
| 1024 A2 | 33.003 | 0.586 / 1.946 / 3.891 | 17.213 / 25.081 | 517 / 410,350 |

Unlike the microbenchmark, the integrated stage listener does not classify cold
versus reused attachments; the table includes every measured loading attachment.
All four startup/configuration/save/shutdown checks pass, with no dropped stage
samples or error/leak diagnostics. No competing engine/compiler was observed
in the retained one-second host samples; the idle Project Manager was excluded.
This does not establish an idle OS or exclude subsecond interference. GPU clocks
and temperature varied: whole-run median graphics clocks were 2212.5, 2310,
2295 and 2250 MHz; median temperatures were 59, 62, 64 and 66°C. These are not
phase-aligned hardware controls. Peak process-private commit was 4.172–4.188 GB,
dedicated GPU allocation about 1.752 GB. Short clean exits do not prove endurance.

All pairwise comparisons have zero mismatched triangle hashes for their shared
terrain sections (224–280 sections per comparison). Final resident sets differ,
even between equal-size repeats; these are asynchronous whole-world runs, not
identical final physics workloads. Total shape counts and frame differences
therefore cannot isolate a piece-size effect. Engine static memory was about
849–851 MB at 1024 and 857–858 MB at 512, also with different resident sets.
The engine physics monitor is retained as a monitor value, not per-tick timing.

Decision: retain 1024. Smaller pieces reduce typical individual attachment
time but do not establish a whole-frame improvement, consume more resident
shapes, and still have outliers. Loading attachment totals are 212–225 ms in
all four runs; reducing the indivisible unit alone does not remove that work.
The earlier [256-piece contact comparison](../../docs/evidence/actor_collision_piece_size/README.md)
already found mixed contact costs and substantially more shapes. There is no
justification to rerun size tuning or change production on the microbenchmark.

The remaining outdoor stalls are demonstrably not all terrain staging: B's
entire sweep has staging maximum **0.020 ms**, yet frame maximum **31.629 ms**;
A2 has staging maximum **0.139 ms** and frame maximum **25.081 ms**. Viewport
render CPU p99 is 9.698/7.555 ms in those runs, and the retained physics monitor
also reports substantial work. These observations prioritize finer physics and
render/wait attribution; overlapping or delayed monitors must not be summed or
assigned as exact causes of the maximum frame.

[Full run identities, distributions, census comparisons and image hashes](terrain-collision-partition-2026-11-09.json).
[Host process/GPU evidence and retained driver](../../reports/performance_changes/host_collision_partition_abba_20261109T194447433621Z/result.json).
The eight views inspected were each run's final `arrival.png` and
`outdoor_2.png`: [A](../../reports/performance_changes/20261109T194447597636Z_collision_1024_a/),
[B](../../reports/performance_changes/20261109T194618181679Z_collision_512_b/),
[B2](../../reports/performance_changes/20261109T194749113487Z_collision_512_b2/),
[A2](../../reports/performance_changes/20261109T194917764026Z_collision_1024_a2/).
They show the same building frontage, road, hillside cover, trees, boulders and
held pickaxe without an obvious missing asset. Wind and final camera yaw differ
slightly. Intermediate views were retained but not reviewed in this pass;
continuous visual seamlessness and world-design acceptance are not established.

## Remaining gates

Return to whole-frame physics, rendering and draw waits using the rolling trace
with recorder-off controls. Total recorder overhead, dense explosive/collapse
loads, pursuit and long-session memory remain open. If a future publication
algorithm changes collision ownership or boundaries, require real walking,
slopes, mining, cave/stair contacts, atomic mesh/collision readiness, cancellation
and edit recovery before admission. Those contact checks were not run for this
rejected size-only candidate. Identical triangles alone cannot close them.
