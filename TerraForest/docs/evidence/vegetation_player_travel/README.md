# Actual player vegetation travel — 2026-10-19

Saved southern_mixed_42_20261018, read-only temporary session, fullscreen 1920x1080,
60 FPS cap, RTX4050. Normal player W+Shift controls drive a 66 m target route east
from (1024,62,1792); actual distance 65.025 m within the ordinary 1 m arrival tolerance.
No teleport after initial staging, no camera-only movement, no save mutation.

Engineering passes: three visited 32 m owners / two boundaries, grounded all 387
sampled frames, at most 81 resident cover owners and four support requests. Arrival
settles without rejected publication. All nine species fit native render byte
budgets with zero budget-deferred pages. Gathered/authored storage remains identical.
This does not assert zero missing pages on every travel frame or prove visual
absence of popping: start/end screenshots are not temporal evidence.

Timing: p95 17.217 ms, worst 37.43 ms during travel. Loading, initial settling and
screenshot readback excluded. This fails strict sustained 16.67 ms frame acceptance;
no old-laptop/thermal or broad world-scale claim. Per-frame CPU/GPU attribution is
still needed before assigning the spike to vegetation.

Visual endpoint inspected: nearby sparse groups and shadows are present; distant
cover remains visibly speckled with repeated spatial patterning. This is recorded
as unresolved art/LOD continuity, not accepted by engineering success. Preserve
candidate density and user-approved sparse direction when addressing it.

Initial test reached 63.045 m and stopped before the second boundary due to its 1 m
arrival tolerance. The assertion failed correctly; extending the target by 2 m
produced the required crossings. Failure log retained; no product fix was inferred.
