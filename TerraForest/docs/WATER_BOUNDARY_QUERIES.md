# Water boundary-query correction

Status: required native implementation, not completed. The retained analytic
regression proves dry answers beneath visible water, including at1.1m and2m depth.
Evidence: [shoreline baseline](evidence/water_shoreline_queries/README.md).

## Required behavior

A connected fluid region below fill elevation must include partial terrain cells
at its boundary. Queries must reject solid ground and disconnected air, including
closed cavities below a visible water surface. Smooth surface geometry, immersion
and vegetation exclusion must derive from compatible connectivity. Cache restores
must reproduce the same classifications. No live terrain read or per-frame mesh
scan is acceptable for a point query.

## Next implementation

Use a bounded piecewise-linear subdivision of mixed cells with explicit face
connectivity (a consistent tetrahedral decomposition is the candidate). Track which
subregions are connected to the lake seed. Fully wet cells retain a cheap path;
partial-cell queries use a bounded local interpolation test. Keep the existing
finite domain, lake-count cap, worker ownership, stale-result checks and edit
invalidation. Share boundary samples where practical; measure worst-case retained
memory before claiming efficiency. Avoid an unconditional finer whole-volume grid.

A vertical extrusion of the surface mesh is rejected: it would wet solid terrain
and disconnected chambers beneath the surface. Merely interpolating density in any
cell neighboring a wet cell is also insufficient: mixed cells may contain separate
air components. Lowering the mesh back to whole-cell borders would hide the symptom
by regressing the accepted smooth shoreline.

The implementation needs a versioned rebuildable bake representation. Older cached
packets must be rejected/rebuilt or explicitly decoded without silently changing
meaning. Canonical lake definitions and IDs should remain compatible. Do not change
the compound world save format just to store a derived boundary representation.

## Acceptance gates before integration

1. The retained visible-water/free-space query fixture passes with cold and restored
   bakes; keep its original failure and exact sampled inputs.
2. Analytic solid points, sealed cavities, disconnected basins, thin walls, both
   sides of shared cell faces and water-level boundaries classify correctly.
3. Open-boundary detection remains conservative and documented; subdivision must
   not silently leak a formerly sealed lake or fabricate unseen water.
4. Native limits bound allocations and query work. Record full/partial-cell memory,
   mixed-boundary bake time and point-query cost; retain expensive cases as failures.
5. Cache malformed/stale/truncated payload checks pass, then real generated-world
   cave edit/reload/fresh-process checks and player/vegetation integration pass.
6. Rendered shore inspection preserves appearance. Keep static-fill/no-flow limits;
   this work does not introduce drainage, conservation or regional fluid simulation.

After one implementation/verification cycle, reassess any unresolved topology or
cost failure rather than accumulating unrelated water features. The full project
coverage register remains authoritative; this correction does not certify water,
large cities, multiplayer or sustained60FPS.
