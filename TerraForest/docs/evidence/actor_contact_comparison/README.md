# Controlled actor cap and contact comparison

2026-10-15. Runtime code unchanged. The fixture fixes its active and background
caps at 60 and records actual cap and window focus on every rendered frame.
Production background power saving remains unchanged. Physics callback sampling
from the preceding correction remains active, including catch-up ticks.

Source: original mixed-neighborhood stage
`combined_stage_7801173ed84740ee91a1b06e51a3298b`; each run uses an exclusive clone
and verifies the source hash afterward. All three source checks passed.
1920x1080 fullscreen, current native builds and engine identity recorded in run
metadata. Gates were not relaxed.

## Normal workload

`baseline` completes with two actor-budget failures. All sampled caps were 60;
focus changed during nearby64 but no background cap change occurred. Frame p95
returned to 17.85 / 17.92 / 18.23 ms for empty / moving16 / nearby64. This supports
background throttling as the earlier 15 FPS explanation, not a runtime speedup.
Moving16 actor/frame p95/max: 1.548/4.143 ms. Nearby64: 1.717/10.152 ms.
Frame maxima remain 23.24/49.22/56.26 ms; passing the existing 18.5 ms p95 gate
does not prove a strict 16.67 ms frame deadline or sustained 60 FPS.
Catch-up frames contain 2–4 actor ticks and are correctly included in costs.

## Contact experiment

The runner now exposes `--compare-contact`. The existing fixture restores the
same 16 actor records for terrain / flat box / terrain. Its box uses collision
layer 128; actor masks switch to that layer only in the box phase. Navigation
and readiness still query the world. This isolates the body contact surface
approximately, not all AI or all scene collision work.

Both comparison runs fail their >4 m movement gate in all three phases.
The second run adds exact travel/height and route diagnostics to the retained
measurements; it was not a retry to obtain a passing result.

| Diagnostic phase | Actor p95 ms | Motion p95 ms | Forward distance m |
|---|---|---|---|
| Terrain A | 1.411 | .820 | 3.295–3.585 |
| Box | .894 | .270 | 3.373–3.627 |
| Terrain B | 1.358 | .844 | 3.355–3.627 |

All actors remained grounded (height error approximately -0.05 m), following
routes with zero reported stuck time. Distances are similar between surfaces,
but below the fixture requirement. Do not mark movement correctness complete.
The consistent cheaper box contact supports terrain contact as a cost source;
it does not justify replacing terrain collision with a box, weakening collision
readiness, or increasing the 16-body cap. No runtime optimization is claimed.

Next investigate the shortfall in route travel and then evaluate collision
changes against stairs, obstacle safety and these preserved measurements.
Water, human saves and runtime presentation settings were not modified.
