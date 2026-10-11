# Conserved geometric water-remapping plan

2026-10-11. NativeWaterRemapPlan computes where existing settled water overlaps
replacement terrain geometry. This is a migration plan, not an ownership transfer.
The source remains the sole quantity owner; the destination must be empty.

Each old wet tetrahedron is clipped by old positive density, its settled water
height, replacement positive density, and replacement ceiling. The shared clipping
kernel interpolates both density fields through every generated vertex. Retained
volume maps to replacement global storage leaves. Displaced water is kept explicitly
as target -1, including unavailable destination regions or storage above its ceiling.
It is not discarded, automatically teleported, or simulated as runoff.

Rows are (old component, destination global leaf, integer millilitres). Geometric
weights are normalized per old connected wet component to its canonical quantity;
cumulative rounding and an exact final residual preserve every ml. This normalization
is necessary because capacity profiles are interpolated and rounded, so their level
need not integrate to exactly the canonical quantity. Both geometric_source_ml and
profile_geometry_difference_ml are reported; interpolation accuracy is still open.

Work is sliced by old tetrahedron and allocation row, with a soft 2 ms check every
16 operations and an explicit 65,536-entry sparse overlap cap. Four half-space clips
produce at most 81 tetrahedron pieces per source tetrahedron, using fixed stack
scratch. Empty source plans complete without scanning geometry. Completed plans do
zero further work. This serialized API is not thread-safe. It currently scans the
source active set; dirty-region localization and worst-case frame/thermal acceptance
are not proven. Caller-owned completed plans retain their bounded scratch until
released. No per-frame liquid voxel simulation is added.

Source mutations and destination water/ownership changes invalidate partial and
completed plans. Old source geometry may be stale: immutable pinned snapshots are
needed to describe pre-edit water. Busy source pours/withdrawals are rejected;
transaction scheduling must resolve their accepted/pending accounting before migration.
Plans do not debit buckets or alter either water state.

## Evidence

141 network/remap checks pass in debug and clean release. They include identity,
excavation, raised terrain, complete solid displacement, budget-one determinism,
stale source geometry, invalidation, empty-state work avoidance, and no duplication.
The raised-terrain fixture keeps 913,333,333 ml in overlap and explicitly retains
334,666,667 ml displaced from an initial 1,248,000,000 ml.

The native TerrainCore integration fills a radius-4 cavity across two owned regions,
removes 1,000 ml, excavates again at radius 5, independently resamples and republishes
both regions, then computes a remap from the now-stale original network. All
129,856,198 ml map into the enlarged cavity; none are displaced or created.
The plan requires 2,203 work units. Source quantity remains unchanged and the
replacement network remains empty until a future atomic transfer is implemented.

The standalone tests/water_clip_intersection.cpp analytic oracle passes 2,462 cases:
axis-aligned intersections against product volumes and oblique plane intersections
against the analytic distribution of x+y+z over a unit cube. Maximum absolute error
was 4.38e-16 cubic units. Compile it with the pinned Zig C++ compiler, C++17 and -O2;
no Godot SDK is required. Existing 49-check water_capacity regression passes.

## Next gate (not complete)

Stage and settle destination allocations, retain and route displaced/overflow water
under durable spatial ownership, then atomically retire old ownership and publish
replacement state. Recheck generations at commit, cancellation, and save boundaries.
Only after this is connected to world scheduling, rendering and bucket/item storage
can live mining or bucket gameplay claim conservation through edits. Current playable
lakes remain static; this test is headless and does not qualify runtime GPU usage,
60 FPS, transient flow, long-run stability, or multiplayer.

Original implementation remains 0BSD; no external fluid library or license added.
