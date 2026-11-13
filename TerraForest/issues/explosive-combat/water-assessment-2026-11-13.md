# Volumetric water assessment — 2026-11-13

- Status: Investigated; implementation and visual acceptance remain open.
- User requirement: efficient three-dimensional water that responds to terrain
  destruction/addition; elaborate flowing-water effects are unnecessary. Major
  architectural changes are authorized where justified.
- Scope: current source inspection and a small independent numeric diagnostic.
  No native rebuild, installed-package change, saved-world edit or new capture.
- Existing reproduction/evidence: [blast-water investigation](distance-water-2026-11-10.md).

## Findings

Water is volumetric in storage, but its current behavior and rendering do not
reliably satisfy the requested result. A flat resting lake surface is reasonable;
a suspended slab after excavation or an invisible remaining quantity is not.

1. `NativeRegionalWater::Region` stores 512 integer water quantities per 4 m
   region (0.5 m cells), with terrain and structure occupancy. It is a sparse 3D
   store, not one outdoor height map or a single plane. Its renderer emits top,
   side and bottom boundaries. Replacing only the shader cannot fix these defects.
2. `combat_world.gd` gates settling behind `--blast-water-settling` or
   `--terrain-water-settling`. Both default off. `lake_world.gd` connects committed
   terrain changes to that gate. Normal occupancy invalidation updates contacts
   but does not move quantities into newly empty neighboring cells. Suspended
   water after a blast is therefore consistent with the default implementation,
   rather than evidence that the explosion forgot every water notification.
3. `build_surface()` rasterizes occupied volumes into a 25 cm density lattice,
   offset by 12.5 cm, then uses the terrain surface extractor. A thin volume can
   lie entirely between samples. Every sample is outside, so extraction cannot
   produce its boundary. The published query geometry derives from that surface;
   agreement between mesh and picking does not prove coverage of stored water.
4. `accept_patch()` explicitly subtracts water replaced by added terrain or
   structures. The optional solver does not make this conservative: deletion
   precedes redistribution. This needs a deliberate displacement policy.
5. The source prototype transfers downwards and horizontally through prepared
   face openings, retaining integer quantities and pending work. It already has
   useful persistence and local wake machinery. Its 256-face allowance and 1 ms
   deadline are cooperative, checked between operations; they do not bound an
   individual face solve, mesh rebuild or overall frame.
6. Terrain contact profiles have conservative fallbacks for ambiguous walls and
   ceilings. A 3D cell store does not prove arbitrary sub-cell cavity topology.
   Cave/overhang qualification must include disconnected spaces inside a cell.
   Likewise, the down/horizontal prototype is not a general pressure solver for
   upward displacement or communicating submerged passages.

Relevant source: `addons/volumetric_water/native/regional_water.hpp` (`Region`),
`regional_water.cpp` (`accept_patch`, `settle_after_edit`, `settle_cell`,
`advance_settling`, `build_surface`), `water_cell_profile.hpp` (`make`),
`addons/volumetric_water/lake_world.gd`, and
`addons/player_runtime/combat_world.gd`.

## Verification and limits

Read the current code against the retained November 10 evidence. An independent
Python interval diagnostic, run without allocating artifacts, reproduces **984
of 1,000 vertical phases missing a 4 mm film** with the current float32 lattice
expressions. This confirms the representational failure, not the percentage of
water missing in a real lake. The initial double-precision calculation gave 985
and failed an exact-984 assertion; matching the C++ float expressions resolves
that boundary-rounding discrepancy. The retained native diagnostic and its
source are `reports/water_surface_sampling.log` and
`tests/native/water_surface_sampling_probe.cpp`.

Existing prototype evidence reports conserved 7,619,860 ml in its crater fixture,
4,376 transfers, and approximately 40–42 ms total settling work spread over
updates after optimization. Maximum measured calls of 956/1,120 us do not prove
a hard 1 ms bound or gameplay frame headroom. Those are historical measurements,
not fresh timings. Existing surface tests have 14 failures in both candidate and
baseline; they remain unresolved, not waived.

No new screenshot or actual explosion playtest was captured. Installed water's
source-only/default-off status is taken from the linked rollout evidence; this
assessment does not independently certify the currently installed binary hashes.

## Recommended architecture

Keep the native regional quantity owner, terrain sampling, immutable publication,
save ownership, and local work scheduling. Replace the lossy water-to-uniform-
density rendering adapter and complete terrain-driven redistribution. A complete
water-store rewrite or migration into TerrainCore is not justified by the
identified failures alone.

Use explicit occupied-volume boundary extraction: derive exposed tops, sides and
undersides from water heads and prepared terrain/structure clipping, union shared
wet faces, and preserve separate connected components. Thin volumes must retain
distinct boundaries even when they share a terrain sampling slab. This is a
design direction to qualify, not a claim that the isolated exposed-sheet helper
already solves topology. One global height-field surface would lose caves and
stacked water. Sharing geometric primitives with terrain remains useful; forcing
both materials through identical sampling does not.

Use event-driven, bounded settling toward a supported rest state. Sleeping water
does no solver work; terrain changes wake affected connected water and propagate
only where necessary. Slow bounded convergence is acceptable; fake completion,
lost quantities and permanent floating remnants are not. Waves, splashes, full
velocity fields and visually elaborate streams are unnecessary for this request.

Added solids need conservative displacement. Stage the edit and water remap,
retaining displaced quantity until reachable capacity is available. If there is
no valid destination, retain explicit pending work or reject admission; never
silently delete water. Upward redistribution needs a capacity/connectivity path
or bounded hydrostatic solve beyond the current five outgoing directions.

Move feature ownership out of combat configuration into the water/world service
when integrating the default behavior. Mining, explosions and building edits
must obey the same committed-revision and pause/loading rules.

## Implementation order and acceptance gates

1. **Representation first:** replace the sampling adapter behind a controlled
   implementation switch. Require finite-film coverage, watertight exposed sides
   and undersides, shared region seams, disconnected/stacked cavities, terrain and
   building contacts, and matching rendered/pick/immersion state. Reconcile the
   existing 14 failing surface assertions without weakening required behavior.
2. **Conservative edits:** qualify the local settling prototype and add solid
   displacement/overflow handling. Test crater under a lake, bank breach, tunnel,
   added dam and enclosed displacement. Account for all quantities at every
   committed transition, including bucket changes and unavailable neighbors.
   The large-edit wake path currently returns for bounds spanning more than 512
   regions; segment or explicitly defer such work instead of treating it as done.
3. **Bounded publication and persistence:** test interruption, pause, edits during
   settling, save/reopen mid-operation, region retirement and ocean boundaries.
   Queries must see one coherent published revision. Profile sampling, solving,
   meshing and upload separately. Make expensive operations resumable or move
   immutable work to workers where measurement warrants it; preserve cancellation.
4. **Actual gameplay:** replay the reported barrel/lake case plus mining and
   deposition with before/after views above and below water. Measure p95/p99 and
   maximum frame times, mesh/queue memory and settling latency alongside combat.
   Demonstrate zero idle solver work and locality as the number of resting lakes
   increases. Native accounting passes cannot close visual or 60 FPS acceptance.
5. **Rollout:** verify source/debug/release and packaged checks with matching
   libraries, migration and unchanged saves; enable by default only after the
   preceding gates pass. Preserve previous/rejected captures and obtain user
   review of the actual water result.

Resume with the representation fixture and connected boundary extractor. The
prerequisite for default terrain response is visible/queryable finite water;
the return trigger is this renewed water request. This assessment closes the
diagnosis/recommendation task, not implementation or visual acceptance.

Authorship/provenance: original AI-assisted repository assessment based on local
code and retained evidence; no imported implementation or assets.
