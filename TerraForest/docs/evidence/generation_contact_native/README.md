# Generation-internal contact policy — 2026-10-25

Engineering integration passes. World quality remains rejected/incomplete.
The candidate is **road_grid=3 / recipe v4**, not the normal selector default.
The existing two independent terrain/road switches still select terrain 22/23
and road_grid=2. No saved world is regraded and no placement rules change.

## What runs where

- `generation_contact.hpp` owns the native overlap preference and contact error
  calculation. Terrain height evaluation calls its inline shaping function.
  This is an exact extraction of existing terrain math, **not a new terrain
  geometry improvement**. Twelve seed/profile fixtures (5,040 points) preserve
  height and material bytes, including in the release DLL.
- The experimental native road solve adds nine-sample, metre-grid footprints to
  its existing bounded grade iterations. It chooses the road/support grade
  before the existing earthworks bake. It does not inspect or repair a finished
  world, add a loading stage, or change terrain when a player places a block.
- Footprints cover the flat support bed, not only asphalt. Settlement envelope
  dimensions come from the same descriptor used by the baker. Regional pavement
  uses the corresponding soil-support descriptor. Both surfaces receive the
  same solved coefficients. Protected entrance tests use projected corridor
  bounds; previously an unnecessary lateral three-metre expansion froze grades.
- Gap and burial remain separate errors. The solver's preferred band is 2–18 cm
  above an integer base; the diagnostic acceptance limits remain 10 cm gap and
  25 cm burial. These are not new placement restrictions. Curvature, grade,
  displacement, cut/fill and protected entrance limits are not relaxed.
- Coefficients/basis weights are computed once per planning call, not per
  iteration. The unchanged iteration budget is 160 with twelve projections.
  At most 32,768 footprints are admitted (about 13.5 MiB of sample data); the
  default seed uses 12,325 (5.08 MiB). Data is temporary, not a per-frame cost.
- Binary recipe v4 distinguishes this candidate from v1/v2/v3. Plan cache v10
  remains checksum- and native-binary-keyed. Warm-cache tests prove identical
  grade reports/digests without rerunning generation. GDScript passes descriptors
  and assembles the existing plan; the footprint solve is C++.

## Measured results

One cold planning run per seed on this machine, then one warm cache read:

| Seed | Current default | Candidate | Cached candidate | Unfit support cells, default → candidate |
| --- | ---: | ---: | ---: | ---: |
| 1703 | 938.7 ms | 1037.0 ms | 51.4 ms | 1481 → 1445 |
| 42 | 1165.2 ms | 1259.1 ms | 115.6 ms | 1713 → 1653 |
| 9137 | 1114.2 ms | 1296.4 ms | 124.5 ms | 1711 → 1674 |

These are whole planning-call timings, not full generation/loading timings or a
statistical benchmark. The added objective costs about 94–182 ms in this run;
there is no claim of zero CPU cost or an overall loading speedup. Cached reads
are not billed as solver time. Identical footprint sets are compared, including
regional support/trails. The latter are measured but trails are not optimized.
The independent audit evaluates full piecewise curves across section boundaries.

Debug and release physics tests each sample 1,209 rays for each mode. No ray is
missing. The candidate's maximum surface error is 1.10 cm and join-step error
0.54 cm. Approved building origins and exact plate records are unchanged.

Production generation/save/reload passes 32 checks in one native window, including
every approved A2 R2, B1 R1 and B2 R2 block. The separate world is
`GridPreference_1703_2fd72a4b`; Wild_Hills is untouched. Read-only review also
leaves that new world unchanged. Of 45 measured final collision footprints,
44 meet the diagnostic limits. The reported regional cell has 18.91 cm burial.
The reported shoulder improves from 39.82 to **30.12 cm**, but **still fails**.
The wrapper correctly returns FAIL despite zero engineering failures.

All four captured images were inspected. They show actual placed blocks and
smooth roads, not replacement assets or fabricated previews. They do not grant
human visual approval or demonstrate universal contact. The remaining shoulder
is retained as a rejected case rather than hidden from the audit.

## Remaining work and rejected trials

The three-seed improvement over the current default is modest, not a completed
solution. Keep the candidate out of defaults. Return to this work with final
composed-surface coverage and a bounded treatment of transition zones: outer
shoulders, end caps, crossings, yards, protected entrances and the wider natural
terrain still lack a universal contact guarantee. No support mounds, per-click
corrections, loosened thresholds or grid changes are authorized substitutes.
See the feasibility contract in `../../PLACEMENT_STANDARD.md`.

Trial 1 and trial 2 regressed seed 1703 (1481 → 1515 and 1481 → 1502 unfit
cells in their earlier section-local audit) and were not promoted. Their reports
are retained. Current reports use full-curve evaluation and must not be compared
to those earlier local-extrapolation totals as if the measurement were identical.

## Evidence and reproduction

- `legacy_capture.json` records the original DLL hash used for the immutable
  `legacy_heights.bin` fixture, before the implementation was compiled.
- `legacy_debug.json`, `legacy_release.json`, `network.json`, `native_debug.json`,
  `native_release.json`, `recipe_release.json`: targeted checks and measurements.
- `legacy_check_run.json`, `network_check_run.json`, `native_check_run.json`:
  final test commands, source provenance and native DLL hashes.
- `generation.json`, `generation_run.json`: production creation and reload.
- `contact.json`, `review_run.json`, and four PNGs: integrated collision and views.
- `trial1_network.json`, `trial2_network.json`: rejected candidates.

Generation/review evidence precedes the final metadata-only completeness guard,
move-without-copy optimization, and extraction of the identical support descriptor.
Final binaries rerun native physics, byte-identity and three-seed plan/cache tests;
those changes do not alter solved grades or the baked review world.
Existing connected-road-network and legacy road-normalization regressions pass.
Pack export and startup smoke pass with all fourteen external native libraries;
the importer still reports pre-existing duplicate UIDs in an ignored historical
ramp snapshot under reports. No source identity was changed to hide that warning.

Run `tools/run_godot_check.py` with tests `generation_contact_policy`,
`generation_footprint_network` and `connected_road_native` in headless mode.
`tools/test_native_release.py` supports the first and third with addon
`volumetric_terrain`, and `world_recipe_native` with addon `world_runtime`.
For the separate full-world candidate, run `world_recipe_generation` with
`-- --footprint-review`, then `python tools/review_grid_preference.py`.
F6/F7/F8/F9 in interactive review visit the town road, natural terrain, reported
regional road and reported shoulder. Do not replace the user's original world.
