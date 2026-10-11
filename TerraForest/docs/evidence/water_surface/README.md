# Finite-water regional surface meshes

2026-10-11. NativeWaterSurface builds one owned 16-cubed region from a settled
NativeWaterNetwork. It snapshots component heads, sections each participating
terrain tetrahedron at that head, clips its polygon against positive terrain density,
and emits horizontal free-surface triangles. Fully positive cells at the same level
are greedily combined into rectangles within their region. The output is Godot
Mesh arrays with upward normals, clockwise front faces and world-space UVs.

Generation is sliced by cell, rectangle candidate, then output vertex. Invalid
budgets do not mutate the builder. Water changes or geometry invalidation reject
unfinished and completed snapshots. Empty water creates no geometry or cell work;
completed builders do no further work. Runtime scheduling must explicitly request
new meshes after a state change, then publish them with the matching water version.

A single region bounds geometric output to at most 221,184 vertices (six tetrahedra,
at most three clipped triangles each per cell). Deques avoid repeated contiguous
triangle-buffer growth. Final packed-array allocation is still one bounded bulk
allocation; conversion is sliced afterward. Scratch remains until builder release.
GPU upload, retirement, pathological-region allocation tails and actual frame-time
acceptance are not yet qualified. No per-frame liquid rebuild has been introduced.

265 network checks pass in debug and clean release. Mesh checks cover area, height,
front-face orientation, wet triangle interiors, output identity under a one-unit
budget, invalid budgets/state, flat rectangle reduction, empty-state fast path, and
a fractional-height cave surface which omits the drained cave. The two-region lake
uses 291 vertices per region. Its surface is 335 square metres: the nominal 28 by 12
extent has two half-cell corner triangles with zero density under the existing
piecewise-linear terrain representation. The initial 336 expectation was incorrect;
point queries confirm those omitted corners are terrain, not mesher holes.

The initial cave check sampled 1 mm below every shoreline triangle. For seven very
thin triangles that point was already solid cave floor. Sampling 1 micrometre below
the surface agrees with the shared density query; no geometry change was required.
This is a test correction, not a claim that narrow shallow-water geometry is absent.

Actual TerrainCore excavation/solid-placement handoffs now also build both regional
surfaces, verify their new heights and create ArrayMesh resources successfully. After
excavation the regions have 315/387 vertices; after underwater solid placement,
636/552 vertices. These are headless geometry/API checks, not rendered visual QA.

Next: integrate native compilation, finite state and matching surface publication
with world scheduling, bucket/item interactions and persistent terrain/water
transactions. Main-world lakes still use the old static runtime. Shader appearance,
water-camera immersion, visual transitions, surface LOD, streaming boundaries and
sustained 60 FPS/thermal acceptance remain unverified. Original implementation is 0BSD.
