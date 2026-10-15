# Straight waypoint progress, 2026-10-15

The instrumented baseline exposes the active waypoint index, target and stall
state. It finishes 12/16. Actor 10 passes x=811 at 4.2 seconds while avoiding
others, continues chasing that sample until roughly 7 seconds, then is carried
back towards x=805 while trying to regain the next sample. The 4 cm mandatory
intermediate targets force repeated backtracking in the opposing crowd. This
trace identifies a route-following failure; it does not isolate all RVO behavior.

The native follower now accepts a 15 cm radius or a passed target plane within
35 cm lateral distance and 50 cm longitudinal distance, only for straight,
level intermediate segments. Segment directions must agree (dot > .999),
segment height changes must be <5 cm and actor height error <10 cm. Corners,
stairs and final targets retain the previous precise behavior. Actual body
collision, terrain readiness and shared route budgets remain authoritative.
Status dictionaries expose waypoint progress only when requested.

The unchanged 720-physics-update settlement check now passes: 16/16 arrivals,
minimum separation 0.786867 m, route work <=12, active bodies <=16, no readiness
holds. Independent frame p95/max 17.678/55.052 ms; profiled adapter p95/max
0.869/1.401 ms. Both existing cost gates pass this run. This is one bounded
regression, not crowd-scale, thermal, endurance or hitch-free qualification.
The 55 ms maximum remains a limitation. Do not infer a general speedup from
one before/after timing sample.

The actual cottage stairs, raised interior and one-metre doorway regression
also passes all six checks. Debug and release extensions rebuilt against the
existing prebuilt SDK. Fullscreen 1920x1080, 60 FPS cap. Source gameplay save
hash unchanged in both manifests. Water and persistence formats unchanged.

Before and after raw traces, manifests, logs and final screenshots are retained.
The final after screenshot was inspected; actors occupy their opposite ends.
Next: integrate a useful settlement actor interaction/order loop and retain
these movement gates; do not use this result to increase the active-body limit.
