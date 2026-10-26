# Vegetation response to terrain edits — 2026-10-26

## Change

- Capture individual resident clumps and tree roots in the edited volume, not
  whole owner cells or canopy boxes. Native probes use the actual edited density
  and voxel occupancy before and after the same ordered terrain transaction.
- Excavated support or newly buried/intersected stems remove that identity before
  the new terrain mesh becomes visible. Neighbours retain exact transforms and
  fade age. Removal also updates picking, trunk/boulder collision and persistent
  removal records, without free harvest rewards.
  Ground-cover draw buffers update in that publication; tree visual tiers use
  their existing renderer flush, while tree membership/collision update immediately.
- Native filtering runs on the terrain worker; scene publication uses local
  render-page updates. Empty vegetation pages have a bounded 16-node reuse cache
  per collection, with zero instance/GPU transform payload while empty.
- No per-frame forest scan, GPU readback, new save format or world regeneration.
  Asphalt-only exclusion stays reversible; physical destruction stays removed.

## Accuracy contract

The smallest identity is a grass/plant clump, stone or tree, not an individual
mesh blade or leaf. Support probes straddle the root by 8 cm; additional probes
follow the central stem/trunk through the terrain lattice. This is terrain
support/intersection testing, not canopy-triangle cutting. Existing unrelated
unsupported props are not retroactively deleted by a no-op edit. Newly streamed
owners continue to use the existing density-aware scatter path.

## Verification

`final/suite.json` records the packaged run, script hashes and all three native
library pairs. Tests cover sphere/box dig and fill, voxel cubes, paid terrain,
authored plants, tree roots and elevated trunk burial, exact neighbour identity,
GPU membership, storage restoration and unload/regeneration. The populated
maximum brush probes 18,517 instances rather than an empty aerial fixture.

The separate native probe checks verify fused density/voxel/paving results,
revision rejection and read-only storage. Renderer tests preserve survivor poses
and fade through partial residency, page reuse, removal and explicit reset.
`visual/` contains the inspected before/after 12 m excavation. Screenshots are
not FPS measurements: fixture readback and exhaustive identity comparisons stall
the test harness intentionally.

Final results: all 71 functional integrated assertions pass; the 72nd assertion
(populated maximum-brush publication below 16 ms) fails at 17.980 ms in the PCK
and 18.129 ms in the final visual run. The six small tool cases publish vegetation
in 0.263–0.777 ms, with 0.144–0.229 ms capture; the 1,114-instance excavation takes
2.452 ms vegetation publication. Maximum-brush sampling/filtering takes 72.909 ms
on the worker; complete terrain publication takes 923.398 ms, not 18 ms total.

The packaged 1,200 mixed-edit / held-tool / 16-large-volume endurance passes all
35 assertions: 4,873 measured runtime frames, p99 17.467 ms, maximum 44.857 ms,
zero runtime frames above 50 ms. Startup still records 70.298/66.935 ms frames
outside those runtime gates. Release-core checks pass 7,251 operations. Picker
checks pass 22/22; mesh/LOD checks 50/50; render continuity/cache checks 31/31.
The first packaged steep-slope/continuity checks passed their assertions but
failed on a read-only `res://reports` directory diagnostic. Absolute output paths
fix the harness; `final-report-path-rerun` passes both cases without loosening
assertions. The original failures remain in `final/`.

## Follow-up qualification

The native page-retirement follow-up passes all 72 assertions: maximum populated
vegetation publication is 11.685 ms in source and 13.014 / 11.679 ms in packaged
repeats, without changing the 16 ms gate or delaying visible removal. Focused
4,800-edit endurance also passes. See
`../terrain_editing/vegetation_pages/README.md` for the native changes, exact
ownership tests, final evidence and still-unresolved presentation stalls.

## Historical limits and retained failures

- The strict populated-maximum publication target remains 16 ms, unchanged;
  the follow-up above now qualifies it on this machine. At this earlier checkpoint,
  initial publication was 32.514 ms; native filtering, worker preparation and
  page reuse reduced the source measurement to 17.415 ms. Do not label this
  maximum-brush performance gate passed unless the recorded run actually passes.
  The follow-up keeps exact survivors and atomic visible publication while reducing
  the native removal cost; these earlier failing measurements remain unchanged.
- `retained/render-stall` records a 72.921 ms frame; `retained/held-phase-tail`
  retains a held-tool p99 failure. A later quiet run is not a fix for those
  intermittent render/presentation stalls or the existing cold-arrival mining gap.
- Legacy road live-pose equality fails in the original path too: the control
  with new support providers disabled moves one restored root by 0.000366 m.
  Road membership/exclusion checks pass. Do not conflate that grading-precision
  assertion with vegetation removal, or silently loosen its tolerance.
- Finite laptop tests are not multi-hour, lower-end or all-world qualification.
  User saves were not edited. Visual/player acceptance remains separate.
