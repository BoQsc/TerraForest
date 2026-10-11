# Shallow partial-cell source admission

2026-10-11. The failure from ../water_capacity/shallow_source_failure.log is fixed.
The source seed is validated against interpolated positive density in its actual
connected tetrahedron. Connectivity is flooded once at that precision. A separate
pass marks wholly empty connected cells only for fast queries and legacy rectangle
extraction. The previous whole-cell flood and its uint32-per-cell queue are removed
(1MiB less allocated scratch at262144 cells). Finalization remains indivisible;
this change does not claim to resolve its scheduling budget.

Ten focused checks pass in debug and a clean release project:
- A2cm-deep puddle with zero full-air cells admits its submerged positive-air seed.
- Ground and points above fill are dry; smooth surface triangles are nonempty.
- Exact sampled diamond-pyramid integral rounds to533ml and matches measurement.
- Zero-full-cell bake capture/restoration preserves bytes, queries and quantity.
- Solid seed returns-2; partial opening at domain edge returns-3 and publishes no water.
- The measured533ml transfers exactly into a ten-litre container ledger.

That last check does NOT change the rendered lake level: ledger/geometry coupling
and live bucket gameplay are still unimplemented. No fluid redistribution has been
introduced by this admission fix.

Existing water, malformed-cache,49-check capacity and shoreline regressions pass.
The actual generated cave test passes17 checks, followed by3 in a fresh process.
The source saved world remains unchanged. Graphical checks use fullscreen1920x1080
cap60; they are functional checks, not sustained frame/thermal qualification.
Maximum-cell water bake measured72.632ms on this run. Keep prior expensive cases;
this is not a controlled A/B benchmark or proof of hitch-free world edits.

Bake version2 retains the same density, connectivity and mesh meanings; decoder
admission now accepts a valid positive-air seed even when full-cell count is zero.
Terrain/water binary fingerprints invalidate integration caches after this change.
The old seed-must-be-full condition was removed, not the positive-density/mask
validation. Existing closed/open/solid behavior remains covered by regression tests.

Next: a finite amount must determine evolving spatial occupancy, including a
submerged connecting passage, high dry sill, drainage, split/merge and displaced
water. Small-source admission is one prerequisite, not completion of finite water.
