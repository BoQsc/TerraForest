# Same-scene shadow cost isolation — 2026-10-15

**Decision: keep production shadow settings.** The tests isolate draw work but
do not establish a stable GPU saving or explain the earlier intermittent frame
failure. Only the diagnostic script changed.

`python tools/run_godot_check.py tower_density --timeout 100 --require "TOWER_DENSITY failures=0" -- --shadow-comparison`

The 64-tower scene is built once. Camera, geometry, collider residency and timing
instrumentation stay fixed while each shadow phase settles for 60 frames and
measures 120 frames. Main building shadows stay enabled in every phase. The final
baseline restores all model shadows, helping distinguish a setting change from
warm-up/order effects. Neither power state nor background scheduling was controlled.

First comparison (before adding window-only phase):

| Phase | Frame p95 ms | Viewport GPU p95 ms | Draws |
|---|---:|---:|---:|
| Baseline | 20.139 | 7.132 | 833 |
| No model shadows | 16.679 | 3.535 | 502 |
| Baseline repeat | 16.683 | 8.279 | 833 |

That run **fails** the first baseline's 20 ms diagnostic threshold; max frame was
73.401 ms. It is retained. Its baseline repeat shows GPU cost can rise while frame
p95 remains near the cap, so model shadows alone do not explain the frame hitch.

Second comparison:

| Phase | Frame p95 ms | Viewport GPU p95 ms | Draws | Primitives |
|---|---:|---:|---:|---:|
| Baseline | 18.736 | 4.620 | 833 | 850,342 |
| No window shadows | 16.744 | 4.604 | 781 | 573,862 |
| No model shadows | 16.750 | 4.233 | 502 | 392,542 |
| Baseline repeat | 16.691 | 4.476 | 833 | 850,342 |

The second run passes the diagnostic threshold, but is not evidence of a fix:
production code is unchanged. Window-only GPU timing is effectively unchanged;
whole-model savings are much smaller than the first run. Draw/primitive reductions
are reproducible structural effects, while timing remains variable. No GPU-% or
thermal claims follow from viewport timing. This remains isolated building QA,
not a dense combined-world, endurance or older-laptop qualification.
