# Bounded targeting and unchanged-selection reuse

2026-10-15, Godot 4.7.2 Windows x64, RTX 4050 Laptop GPU.

The old pickup pressure fixture assumed seven catalog types. It now exercises
all 23: 94,208 stored records, a combined per-type visible cap of 5,888, and
282,624 bytes for an initial full transform upload. This is not a global draw
budget or a claim that all those objects are cheap to render.

Targeting CPU microcheck (120 samples per phase, 20 warmup calls):

| Dataset | p95 | Maximum | Candidates visited |
| --- | ---: | ---: | ---: |
| One local record | 0.161 ms | 2.017 ms | 1 |
| 94,208 records, others distant | 0.258 ms | 0.385 ms | 1 |
| Dense local cell, rejected | 0.124 ms | 0.251 ms | 1,024 |

The p95 gate is 0.5 ms. Occlusion is a counted stub in this headless component
test: at most one callback for a successful candidate, none on budget failure.
It does not measure physics-ray cost, GPU execution, frame times or thermals.

The separate graphical MultiMesh refresh/readback check exposed repeated native
selection work even when the stores and focus were unchanged. A native spatial
revision now invalidates cached selection on configure, spawn, despawn, movement,
position correction and successful restore. Query center/radius/budget changes
also invalidate. Incomplete budget-limited selections are not cached. Callers
receive independent dictionaries, and publish still checks live handles and
owned GPU resources. Animation and position-only updates retain their paths.

Same-host before/after, 30 stationary refresh samples over all full stores:

| Refresh CPU | Before | After |
| --- | ---: | ---: |
| p50 | 2.740 ms | 0.155 ms |
| p95 | 4.219 ms | 0.185 ms |
| Maximum | 5.195 ms | 0.506 ms |

Unchanged refreshes now visit zero spatial candidates and upload zero transform
bytes. This fixture validates selection/upload/readback, not actual drawing of
5,888 visible objects. Moving-focus and dense visible-world costs remain open.

Entity renderer checks cover changed query/budget, motion, removal/reuse, same-
count restoration with new handles, position correction, external resource
mutation, caller dictionary mutation and cached position/marker behavior.
Entity storage and graphical gait regressions passed. One storage launcher run
used a nonexistent completion marker and was rejected by the harness despite
zero test failures; the corrected-marker rerun passed. Both native debug and
release DLLs were rebuilt against prebuilt godot-cpp, without rebuilding the SDK.
