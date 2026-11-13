# Continuous volumetric water replacement

Status: implemented and installed, 2026-11-13; scoped qualification completed.
Timing overruns and representation limits remain explicit below.
This document completely replaces the previous implementation plan. Historical
plans and failed experiments remain in Git history (through baff9588) and the
existing issue evidence; they are not acceptance evidence for this replacement.

## Required result

Water is a connected three-dimensional occupied volume with one continuous
triangulated boundary, matching the user's isosurface reference. Its visible
boundary must not expose individual storage-cell boxes or horizontal sheets.
A level lake surface is expected; unsupported sheets after excavation are not.
Ordinary barrels, mining and deposition must update water without opt-in flags.
Water must fit the authoritative terrain, including caves and overhangs, conserve
finite quantities, remain stable across save/reload, and have measured bounded cost.

## Architecture and exclusions

- Authoritative terrain density and solid geometry define available 3D space.
  Floor/ceiling-only approximations cannot be the general occupancy authority.
- Finite water quantities and connectivity are separate from surface extraction.
  A shared implicit field and the existing terrain surface infrastructure are the
  initial meshing direction. No visible per-storage-cell boundary renderer.
- Updates are edit-triggered equilibrium transactions with barrier/spill handling,
  not prolonged pairwise diffusion. Settled water performs no redistribution work.
- Changed geometry, surface queries and immersion publish a consistent revision.
  Worker jobs have explicit memory/work limits and retain valid prior state on failure.
- No full fluid dynamics, foam/splash feature expansion or microscopic-film
  topology project. Sub-render-resolution amounts remain conserved in storage;
  claiming every millilitre has independently visible geometry is not a requirement.
- Do not claim marching cubes alone supplies occupancy, connectivity or motion.

## Execution gates

- [x] 1. Recover a coherent source baseline. Audit and remove the rejected boundary
  renderer and unqualified diffusion experiments; preserve unrelated work, saves,
  evidence, and only independently useful verified infrastructure. Rebuild matching
  source binaries. Do not silently reset the whole dirty checkout.
- [x] 2. Prove a continuous implicit boundary. Native extraction must show a rounded
  volume, partial sloping contact, an exposed cut, and a cavity/overhang without
  cell terraces. Use the actual terrain density path for integrated contact tests.
  Inspect shaded and wireframe captures, seams and solid exclusion. A sphere-only
  demonstration does not close this gate.
- [x] 3. Implement finite-volume terrain response. The actual barrel/lake case is
  primary: newly connected excavated space fills appropriately, solids exclude
  water, deposition displaces it, and isolated basins stay isolated. Verify breach,
  split, spill threshold, sealed cavity and blocked displacement cases. Preserve
  exact quantity; explicitly retain unresolved quantities instead of deleting them.
- [x] 4. Qualify runtime behavior (scoped results and overruns below). Test interrupted edits/saves, reload, streaming,
  stale worker results, unavailable regions, region seams and ocean boundaries.
  Measure water CPU/GPU cost separately, peak memory, triangles, first visible
  response, final publication latency and frame tails against the same baseline.
  Initial targets: no idle solver work; <=1 ms main-thread water update budget;
  typical local barrel response within 250 ms after terrain publication. Report
  measured violations and fix their cause; do not silently relax these targets.
  The full scene must retain the project's 60 FPS frame budget (16.7 ms), including
  representative combat. A stationary HUD FPS reading is not proof.
- [x] 5. Replace the default and deliver. Inspect actual gameplay above/below water
  before/after barrels, mining and deposition; verify ordinary launch behavior,
  existing-save migration, debug/release parity and the installed package. Commit
  focused verified changes and explain the remaining scope and human visual-review
  limits. Do not mark complete while required behavior or evidence is missing.

## Delivered behavior and qualification

Runtime `13d0f083` is enabled by default in source and the installed pack.
Ordinary barrels, mining and deposition update conserved 3D water and its
continuous boundary. Geometry, targeting and immersion publish together. The
existing 12-lake save loads and its actual lake explosion settles 43,079 cells
without changing any of its 27,351,242,997 ml or modifying the source save.

Final installed checks: `171254122100Z` (five explosions, terrain edits,
unfinished-save loading, old-cache migration, full occupancy comparison and
closed seams), `171417348374Z` (existing saved world), `171535917653Z` (same
saved world with inspected above/below-water captures). Normal release startup
passes without path overrides. Release libraries pass the same native APIs and
full gameplay cases. Export gates all pass; installed pack SHA-256 is recorded
in [the compact verification record](water-verification-2026-11-13.json).

The final 1920x1080 installed run publishes primary barrel water 247.278 ms
after terrain publication, with 897 us maximum primary water main-thread work.
Shoreline explosion through completed publication takes 225.085 ms. Moving
combat p95/p99/max are 9.334/12.139/17.068 ms; water main p95/max are 776/1173 us.
Water-on GPU p95 is 5.888-6.152 ms versus 4.409 ms off on the same camera path.
Sampled private commit is 3.03 GB and dedicated GPU allocations 1.48 GB.
The controlled boundary has 22,848 triangles, zero open edges and zero degenerates.
Its approximate mesh volume is 552.410 m3 versus 559.128094 m3 owned; meshing
approximation does not change the conserved quantity.

Gate 4 records completed scoped qualification, **not** universal compliance with
every initial timing target. The 1 ms water target and 16.7 ms whole-frame target
have the explicit overruns above; some retained runs also exceed 250 ms.
Major measured causes were corrected (recursive overflow routing, terrain queue
starvation, GPU work on workers, redundant publication work and serial loading).
Strict no-overrun performance acceptance remains open in the broader runtime
performance work; the water feature is functional and installed. Follow up when
representative repeated workloads exceed the frame budget at p99, when water
exceeds 1 ms persistently, or when a bounded-body failure occurs. Closure requires
attributed frame traces and repeatable on/off comparisons, not a HUD FPS reading.

Representation limits remain explicit: 0.25 m extraction / 0.5 m storage, small
contact rims, conserved unresolved thin films, and possible geometric joining at
zero-width diagonal contacts (which do not communicate in the volume solver).
Memory/graph caps preserve valid prior water with a reported failure; unavailable
terrain/solids wait for authoritative data. Distant ocean proxies remain a rendering
optimization, not an infinite fluid simulation. Agent visual inspection is complete;
user visual approval is separate. Earlier failures below remain historical evidence.

### Replacement evidence, 2026-11-13

- `reports/checks/20261113T130056209004Z`: `water_implicit_proof` passes.
  Sphere, native basin, excavation and overhang use continuous triangulated
  boundaries. Agent inspected shaded cutaway and overhang wireframe captures.
  Cutaways hide half the terrain only for inspection; water occupancy uses the
  complete terrain. This is opaque geometry inspection, not water-material approval.
- Closed basin at 40 m3: level 4.228893 m; excavation 4.190556 m; added overhang
  4.301048 m. Integer quantity stays 40,000,000 ml. Rendered boundary volume is
  within 0.00014 m3 of 40 m3 in these cases. Reference solve was about 22-25 ms;
  field extraction about 1 ms. These exclude terrain sampling and GPU cost.
- Initial transparent proof `20261113T124818815446Z` exposed contact/shading
  artifacts. Opaque captures do not resolve that presentation requirement.
- Cutaway capture attempt `20261113T130004883781Z` failed due to a freed scene
  node retained in the fixture list; corrected in the later passing run.
- Worker publication `20261113T131116560844Z` passes with the rebuilt source and resolved water geometry;
  the earlier 1-litre fixture produced empty geometry and failed picking. Small
  unresolved films remain explicit rather than silently claiming full coverage.
- Legacy settling `20261113T130640190896Z` fails convergence and connected-layer
  distribution. Preserve that failure; no default rollout or performance claim.
- Remaining gate-2 work: integrated region seams, quantitative solid exclusion/
  contact-gap checks and the ordinary transparent water material. Gates 3-5
  remain open, including actual barrel response and measured gameplay performance.

## Evidence rules

Use the existing checkout and bounded artifact lifecycle. Preserve failed images
and logs. Compare identical cameras/resolution and separate algorithm timings
from rendering timings. Record actual command, revision, scene and acceptance
scope. Test passes never override visibly broken water. Existing failed evidence:
20261113T121519182354Z (120-second unsettled barrel water),
20261113T122134864331Z and 20261113T122628097255Z (60-second settling failures).

Native convex occupancy probe also passes after recovery. Godot editor import
`20261113T130408650844Z` generated the new script UIDs. Debug DLL SHA-256:
`3fc9087fc90b06e6f779e655f03455ab789f141b3cdef59d5a4d13be534f1daa`.
New native reference code and proof fixture are original 0BSD work; existing
terrain code and development screenshot provenance are preserved.

### Runtime integration in progress, 2026-11-13

The connected-body equilibrium transaction now runs in LakeWorld after ordinary
terrain commits, with barrel response enabled by default in source. It conserves
integer quantity, handles spill thresholds, retains blocked displacement, and
rejects stale workers. Ambiguous terrain cells use clipped 3D air volumes for
walls/ceilings; monotone floor contacts retain the existing terrain triangles.

- `reports/checks/20261113T144344989683Z`: equilibrium regression passes, including
  sealed ceiling, spill threshold, displacement, blocked retention and reload.
- `reports/checks/20261113T144711280976Z`: actual barrel/gameplay path passes
  conservation, downward redistribution and reload. Above-water image inspected;
  stacked sheets are absent in this interior-lake reproduction. Response remains
  592 ms after terrain publication, water main-thread p95 886 us / max 1727 us,
  scene GPU p95 9.30 ms. This misses latency and main-thread tail targets.
- Earlier actual-game passes: `20261113T142135203684Z` and
  `20261113T142641336456Z`; these had worse response latency. The failed launch
  `20261113T144407666944Z` exposed indentation in the terrain facade and is retained.
- Timing identifies mesh dispatch/publication frame roundtrips as the main delay.
  Larger bounded worker groups and shorter upload slices are under qualification.
  No performance gate is closed. Shoreline breach, mining/deposition game captures,
  cache migration, streaming/ocean and installed release remain required.

This supersedes the preceding “next required implementation” paragraph only:
there is now actual-game integration evidence, but the replacement is not complete.

### Additional qualification and corrections

- `20261113T150320522967Z`: actual interior barrel, shoreline barrel, mining,
  carried-material deposition, reload, and full-resampling comparison pass.
  Complete barrel publication: 247.402 ms after terrain publication; main water
  update p95 744 us / max 929 us. Moving combat p95 9.352 ms / p99 11.398 ms,
  maximum 21.335 ms; retain this frame-tail violation rather than claiming every
  frame met 16.7 ms. Water-on GPU p95 5.93-6.33 ms versus 4.51 ms water-off.
- The earlier `145347419553Z` 138 ms latency was invalid: readiness omitted an
  outstanding mesh worker. Readiness now includes worker and publication state;
  a regression verifies that dispatched geometry cannot be reported visible.
- Underwater deposition capture exposed reflective flares at solid contacts.
  Native mesh colors now distinguish free water boundaries from solid contacts,
  including upward-facing submerged ceilings. Visual reinspection is required.
- The old sub-cell contact fixture (`151004427865Z`) has no negative sample on
  the 0.25 m extraction lattice. Its 29,167 ml corner film remains authoritative
  and explicitly unresolved. The replacement test checks that status and adds
  an 80,000 ml resolved partial volume with strict terrain-peak exclusion. This
  implements the stated sub-render-resolution exclusion; it does not claim all
  thin films are visible or reinstate fabricated cell-boundary sheets.
- Migration keeps old geometry caches tagged old until terrain sampling upgrades
  them. Blindly marking every serialized cache v12 broke byte-exact old archive
  expansion and could skip migration; that failure is preserved in runs
  `151028489385Z` / `151044307863Z`, with the corrected codec under revalidation.
- Perched-pocket and higher connected-source discovery regressions were added
  after review of the uniform-level shortcut. No default-release claim yet.

### Runtime qualification continued

- `20261113T152014576568Z` passed geometry/terrain checks but crashed during
  moving combat with Windows heap corruption (`0xc0000374`) and a Godot
  Dictionary `_p` error. This is a failed run, not acceptance evidence.
- GPU mesh creation was moved back to the main thread. Workers now emit indexed
  render buffers, with a regression proving their expanded attributes exactly
  match the published query triangles. Runs `153242820026Z` and `153607971151Z`
  complete the five-explosion scenario without that crash; root cause is not
  proven solely by those passes.
- The latter run's above/below-water captures were inspected. Shoreline sheets
  are absent, the lower reflective flare at deposited solid contact is removed,
  and the boundary follows the crater. A small extraction-scale rim remains at
  the deposited block's waterline. This is agent inspection, not user approval.
- Performance failures remain explicit: `153607971151Z` takes 400.426 ms after
  terrain publication, with 1.330 ms peak water main-thread work and one 128.395 ms
  moving-combat frame. Stage instrumentation is being added to locate that stall.
- Dry unknown frontier regions now block redundant equilibrium jobs while their
  terrain is sampled. Regression `153444785687Z` passes. Indexed render/query
  equivalence and old-cache migration pass in `153502367967Z`.

### Acceptance status after gameplay integration

Gates 1-3 now have integrated evidence: default continuous boundaries, actual
TerrainCore contact/overhang tests, closed game-region seams, finite equilibrium
with barriers/perched pockets, and actual barrel/mining/deposition transactions.
Gates 4-5 remain active until final performance and installed-release checks.
Run `154832906220Z` completes five actual explosions: combat p95 9.734 ms,
p99 11.327 ms, maximum 16.563 ms; water main maximum 305 us during combat.
The primary barrel still takes 314.867 ms after terrain publication, above the
250 ms target; primary water main maximum is 938 us. No latency pass is claimed.

Older game captures are cold-retained in each run's `captures.archive.json`
using the documented lossless retention path. Original logs/JSON remain loose;
archived screenshots have not been discarded. The `154144627442Z` run was blocked
before engine launch by the report budget; no gameplay result exists for it.

- Profiling `155144386402Z` isolated 67.695 ms of repeated recursive overflow
  routing. The replacement records overflow bottom-up and distributes it once
  top-down. In `155532015762Z` that phase is 64 us, with conserved gameplay
  results; total publication is 259.663 ms (still above target). Direct clipped
  spill heights also match independent bisection for oblique 3D contacts.
- Terrain-worker water preparation now receives an 8 ms cooperative quantum
  instead of 4 ms to reduce waiting between short contact slices. This changes
  background-worker scheduling, not the 1 ms main-thread water target. Queued
  mutations/save barriers remain authoritative; nested terrain meshing retains
  its single-slice servicing. Final gameplay qualification is pending.

### Final regression qualification

- `160006861403Z`: actual-game primary barrel publication is 226.176 ms after
  terrain publication; main water maximum 949 us. Combat p95 10.040 ms / p99
  11.726 ms / maximum 17.633 ms. This last overrun remains recorded. Water-on
  GPU p95 5.36-5.81 ms versus 4.08 ms off. Sampled process private commit
  3.18 GB and dedicated GPU allocations 1.48 GB remain within project budgets.
- Final debug checks: worker/query/migration `160413165365Z`; actual native
  crater/overhang `160426634014Z`; contact volume `160441554595Z`; continuity
  `160707175592Z`; captured topology `160836249248Z`; ocean transfer/frontier
  `160848188318Z`; storage snapshot `160859551088Z`; streaming save
  `160910898826Z`; region store `160922399791Z`.
- Continuity run `160455436788Z` retains the obsolete box-envelope failure.
  The updated test explicitly conserves/reports its unresolved 4 mm film and
  uses resolved 250 mm partial volumes for the 510 closure patterns. Its ledge
  fixture now has a resolved 200 mm upper layer instead of a 100 mm layer with
  no negative lattice sample. Distinct resolved pools and ledges still require
  exact separation. Zero-width diagonal edge/point contacts can join in the
  continuous isosurface; they are not communicating faces for the volume solver.
  This is a stated fixed-resolution limit, not a claim of sub-grid topology.
- `160735963837Z` contains a passing topology result but a launcher failure:
  the required completion text used `failures=0` instead of the script's JSON
  field. The correctly configured rerun is `160836249248Z`.

### Installed-game and existing-world qualification

- Export and release-water parity passed, followed by packaged scenario
  `162130193328Z`: all five barrels, mining/deposition, legacy-cache migration,
  save/reload and closed seams pass. Publication 293.854 ms, combat p95 10.745 ms /
  p99 12.121 ms / max 20.863 ms; retain these target overruns.
- Bounded water servicing now also runs between foreground terrain region calls.
  `163021814313Z` publishes in 240.684 ms; primary water max 1.008 ms, combat
  p99 11.310 ms / max 17.590 ms. The longest combat frame spends 0.301 ms in
  water. Bounds calculation was subsequently moved from atomic commit to staging.
  These runs do not prove every full-scene frame meets 16.7 ms.
- Existing-world remote-barrel runs `163242286879Z`, `163630836391Z` and
  `164019699432Z` fail loading. The latter diagnostic proves water stops on
  an unloaded building region (192,10,194), with 1,317 occupancy requests left;
  `solid_hulls` correctly reports unavailable, but no paging interest was sent.
  The previous isolated lake checks did not expose this multi-lake load defect.
  `163145161973Z` never launched because its generic output reservation exceeded
  the report budget; the audited log-only check now declares 16 MiB.
- Correction under verification: water requests exact occupancy data through the
  existing block pager's bounded scan/read/residency budgets, separately from
  navigation interests. Page transfers use logical content revisions so they do
  not cancel unchanged frozen hulls. A separate loading dependency was corrected:
  saved unfinished equilibrium may complete while loading blocks gameplay.
  Neither correction is accepted until the existing world and updated gameplay
  regression pass. Source and installed package must then be refreshed together.

- `164636073509Z`: block-pager regression passes exact occupancy interest,
  authoritative hulls, unchanged content stamps, interest release, navigation
  interest, scan/read bounds, history protection and stale restore handling.
- `164730004367Z`: the existing read-only saved world now loads all 12 lakes.
  The remote three-barrel chain passes without moving the player. An additional
  barrel in the nearest existing lake settles 43,079 cells and preserves all
  27,351,242,997 ml; no occupancy/surface failure. The original save hash is
  unchanged. Sampled private commit 3,600,773,120 bytes and GPU allocations
  1,491,619,840 bytes remain within budgets. This closes the diagnosed load stall.
- `164852715309Z`: all source gameplay assertions pass, including restoration
  and completion of a saved unfinished transaction while loading blocks gameplay.
  Primary publication 262.966 ms / main maximum 914 us; moving combat p95
  9.327 ms / p99 12.596 ms / max 14.624 ms; water main maximum 1,092 us.
  Water-on GPU p95 5.705-6.202 ms versus 4.158 ms off. The 250 ms / 1 ms soft
  targets are not hard guarantees: this run retains those small overruns.

### Final source revision

Runtime, matching native libraries, regressions and bake receipts are committed
as `13d0f083`; validation/retention tooling is `4510a46c`. New original code is
0BSD; existing library and asset notices remain unchanged.

- `170033608468Z`: installed-pack five-barrel/terrain/save/loading-migration
  scenario passes before the final loading-only optimization. Primary response
  214.380 ms, water main max 883 us; combat p99 12.135 ms / max 15.798 ms,
  combat water main max 1,052 us. Keep the small soft-budget overrun explicit.
- Cached building contacts now use batches of up to 32 through the existing
  bounded terrain worker, including partial batches before unavailable solids.
  This removes the former one-rendered-frame-per-region loading requirement.
  Existing-world run `170316295072Z` passes in 27.055 seconds versus 57.221
  seconds in `164730004367Z`, with the same remote chain and 43,079-cell lake
  update; original saved data remains unchanged. This measures the complete
  check, not pure startup time or a universal loading-time guarantee.
- `170415195940Z`: final source five-barrel/terrain/unfinished-save/loading
  scenario passes. Publication 276.784 ms / main max 847 us; combat p95
  10.144 ms / p99 12.105 ms / max 17.597 ms; combat water max 971 us.
  This frame-tail and publication-target overrun remain retained.
- Release parity: `165300883622Z` (pager), `165322292887Z` (full gameplay),
  and `170604540108Z` (existing multi-lake world with batched loading) pass.
  Both water and structures release libraries were selected; original extension
  descriptors were restored byte-for-byte. Full-game release combat p99
  13.956 ms / max 15.516 ms, water main max 971 us. Report:
  `reports/water_final_release_parity.json`.

### Reproducing installed qualification

From the project directory, with the installed pack and matching libraries:

```text
python tools/run_godot_check.py water_barrel_world --executable --timeout 240 --require failures=0 -- --gameplay-construction --water-gameplay --water-bucket-review --water-full-regression --water-performance
python tools/run_godot_check.py combat_remote_world --executable --timeout 240 --require failures=0 -- --verify-water-settling --water-capture-existing
```

The second check requires the existing read-only fixture named in its driver;
it does not overwrite or regenerate that save. Screenshot provenance is in
`images/manifest.json`. The release template rejects `--main-pack` path overrides
(retained failed harness attempt `162015432287Z`), so packaged drivers use the
repository's established root executable. Normal `dist/TerraForest.exe` startup
is separately verified in `reports/water_release_startup.json`; native release
parity is verified in `reports/water_final_release_parity.json`.
