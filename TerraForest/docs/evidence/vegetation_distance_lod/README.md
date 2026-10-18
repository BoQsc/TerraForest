# Continuous density with distance LOD — 2026-10-18

The scatter experiment was rejected and removed. Native candidate positions,
models at near range, authored plants and harvest IDs retain their prior values.
The old policy faded grass at36–56m and generated only one layer in outer cells.
That concealed the existing mesh LOD behind a density/visibility cutoff.

All49 resident owners now receive the same16 candidate layers (50176 candidates
before terrain/structure/water exclusions). The existing near/middle grass meshes
have468/72 triangles. A third8-triangle opaque silhouette tier is appended without
changing near indices/geometry. Actual native-batched renderer counters verify
near468 and distant8, exact near pixels, picking bounds and identical placement
snapshots. Ground cover uses its original arrival fade, with final76–92m distance
fade inside the residency footprint. No alpha cards or new texture assets.

NativeStaticBatch now optionally limits cast shadows by horizontal distance to
page bounds, updated at the existing4m render-selection interval. Zero retains
unlimited shadows for existing prop callers. Grass24m, other cover48m; page extent
and4m selection padding mean these are not exact per-blade cutoffs. Tests verify
actual child shadow settings near/far/return and unchanged placement snapshots.

Integrated readonly seed42 southern world,1920x1080 cap60: all49 owners settle,
zero budget-deferred pages. Grass42693 resident instances,2.73MB transforms,
49 of364 resident pages casting shadows. Initial cover settling13.562s is a real
loading cost increase, not hidden. Timing sample120frames after screenshot readback:
median16.662ms,p9517.943ms,worst18.562ms,GPUmedian7.456ms. No strict60FPS,
thermal,old-laptop or performance-win claim. Native debug/release builds reuse SDK.

Ground and raised screenshots inspected: cover extends past the previous cutoff,
and near grass receives cast shadows. Overall art/shadow quality is not accepted.
64m camera-travel check passes persistence/bounds/admission; full timing retained.
It does not prove absence of every transient pop while walking or driving.

Remaining explicit work: smoother visible LOD/shadow transitions, loading and
prefetch latency, comparison with accepted dense vegetation showcase, lighting
quality near player, and zoom-aware distant coverage. Current far silhouette is
an initial cheap tier;76–92m is not a claim of final viewing-range adequacy.
