# Continuous volumetric water replacement

## Immediate editing architecture correction — November 14

**Implemented and installed; scoped gameplay verification passed.**
The final packaged run `035031045201Z` passes normal sea/lake barrels, actual
pickaxe mining and four bucket actions, including interruption of background
meshing. Sea / lake / mining response is 163.084 / 228.188 / 192.120 ms after
terrain publication; bucket action-to-publication is 39.987–68.268 ms. Original
player-save hashes are unchanged. All fourteen native library pairs match the
source checkout. Export, nine required building contracts and packaged smoke /
house-light checks pass. No desktop input or Steam shortcut changes were made.

[Machine-readable final evidence](water-immediate-verification-2026-11-14.json)
records exact hashes and timings. Moving-camera water-on frame p95 is
14.256–16.388 ms; GPU p95 is 7.022–7.533 ms versus 5.566 ms with water hidden.
Water-main p95 is 0.850 ms. **Strict tail targets remain unmet:** the final combat
run has a 4.074 ms water equilibrium commit (whole frame 15.222 ms), exceeding
the 1 ms soft budget. Whole-game lake p99 is 50.984 ms; sea maximum 152.821 ms
includes a measured 125.479 ms handgun equip with only 0.059 ms water work.
This delivers bounded local response, not an every-frame 1 ms / locked-60-FPS
claim. Further tail optimization requires slicing/preparing the final native
commit and separately addressing non-water equip/terrain/render spikes; closure
requires repeated no-capture moving-combat traces within those original targets.
These remaining performance limits are retained here and in foundation status.

Source verification: local edits publish
without waiting for the connected lake. `033256552641Z` passes normal barrel
placement/handgun explosions at both sea and lake shores, actual pickaxe mining,
and four bucket transactions including interruption of background meshing.
First visible response after terrain publication is 167.948 / 199.065 / 208.160 ms
for sea / lake / mining. Bucket input-to-publication is 43.523–96.114 ms.
Both first-response camera angles at both shores were inspected; these capture
the local response before wider equilibrium, not a later settled substitute.

- Lake first response: [angle one](../../reports/checks/20261114T033256552641Z/player_lake_after.png),
  [reverse angle](../../reports/checks/20261114T033256552641Z/player_lake_after_reverse.png).
- Sea first response: [angle one](../../reports/checks/20261114T033256552641Z/player_shore_after.png),
  [reverse angle](../../reports/checks/20261114T033256552641Z/player_shore_after_reverse.png).
- Block contact: [above](../../reports/checks/20261114T034146103768Z/object_contact_above.png),
  [underwater](../../reports/checks/20261114T034146103768Z/object_contact_underwater.png).

These are engine viewport captures on a separate non-input desktop. The lake
still has a transient depression at first response; wider settling continues.
Paused-capture HUD FPS is not performance evidence. The no-capture camera-path
measurement below is the performance comparison. User visual approval is separate.

`034146103768Z` passes the complete actual-game barrel, mining/deposition,
structure contact, save/reopen, pending settling and old-cache migration sequence.
Its strict boundary audit has 23,452 triangles, zero open edges, duplicate or
degenerate triangles, or off-grid vertices. The earlier three-edge failure is
fixed without relaxing the audit (`033902257122Z` exact-state replay).
Above/underwater block contact and deposition captures were inspected. Water
reaches all four cube walls within 1 cm, and removal restores the boundary.
`034318578996Z` loads the twelve-lake Hidden_Creek save with no capacity failure
and unchanged source-save hash. Continuity (`033902251123Z`) and streaming/save
(`033902247836Z`) pass against the same native build.

Historical attempts and rejected evidence follow; their then-current status
does not supersede the verification above.

The connected-body transaction is rejected as the latency dependency for edits.
Previous correctness passes below do not certify immediate response.

- [x] Separate local conservative response and publication from connected-body
  relaxation. Local discovery stops at a bounded transaction boundary; it must
  not invent water or read unknown terrain as empty space.
- [x] Give buckets and terrain edits priority, including interruption of an
  already running wider solve/publication. Render and picking must agree.
- [x] Measure first visible local response separately from final equilibrium.
  Verify scoop/pour, mining, sea and lake normal barrel gameplay, repeated edits,
  exact quantity, two camera angles and frame cost on the isolated desktop.
- [x] Verify persistence of unfinished relaxation, final package/native parity,
  and commit verified changes without modifying Steam shortcuts or user saves.

Latest status: local latency passes, visual continuity does **not**. Runs
`022357970584Z`, `023314388134Z`, `023930086975Z`, and `025344629909Z`
pass the edit timing assertions but their first-response lake views are rejected
for stepped/rectangular seams. Moving reconstruction before terrain clipping
passes native gradient and terrain-peak closure tests (`025102351514Z`,
`025102369467Z`), but does not resolve the actual-game seam. Do not present
these native passes as visual acceptance. `025344629909Z` measures buckets
35.881–73.771 ms and pickaxe response 192.432 ms. The subsequent no-capture run
`025921236264Z` measures sea/lake/pickaxe 165.516/247.069/190.088 ms.
Terrain timing starts at committed terrain publication, not button-down.
Remaining: diagnose first-response seam; align reconstructed immersion queries;
repeat current contact/persistence/loading/performance checks and package parity.

`030216032261Z`/`030606560027Z` pass published immersion and shared-normal
agreement. `030634707294Z` still has a rectangular first-response boundary, so
shared normals alone are rejected as a fix. A cross-layer linear-surface
regression (`031332096882Z`) fails both geometric-volume and smooth-height
assertions: the old reconstruction stopped at each half-metre vertical layer.
`031558363630Z/local_response.water_regions` preserves the exact normal-gameplay
local state (877,368 bytes). Its full cross-section spans 44.161 to 43.447 m,
crossing two layer boundaries. That diagnostic run also retains a 104.254 ms
active-mesh bucket interruption failure; do not silently omit it from latency
qualification. `031346697523Z` passes save/reopen of unfinished local settling.
Cross-layer reconstruction is under test; no visual acceptance yet.

Cross-layer reconstruction now passes `032424826916Z`, including 510 occupancy
patterns, linear surfaces across vertical layers, geometric volume, shared
normals and published immersion. Actual replay `032151666066Z` has zero height
discontinuities at 14 sampled layer crossings. `032504100432Z` first-response
sea/lake images were inspected from both angles: the earlier stepped/open
rectangular seams are absent. This run still fails lake latency (263.067 ms).
The subsequent no-capture performance run `032936321524Z` passes with
sea/lake/mining 162.581/247.192/191.687 ms and buckets 43.641–57.037 ms, including
active background mesh interruption. Moving water-on/off/on GPU p95 is
6.555/5.215/7.249 ms; water-main p95 is 0.841/0.775/0.846 ms. Whole-game spikes
remain: sea maximum includes a measured 130 ms handgun equip; lake p99 is
52.432 ms with water work below 0.3 ms on its two worst frames. Do not claim a
universal locked frame rate. Latest optimization avoids absent finite-owner
meshing; full current integrated/contact/loading/persistence/package checks
remain required before closure.

`033256552641Z` passes current normal sea/lake/pickaxe latency at
167.948/199.065/208.160 ms; all four first-response shore images were inspected.
`033457375211Z` passes object probes within 1 cm and above/underwater inspection,
mining/deposition, save/reload and old-cache migration, but **fails** the strict
terrain boundary audit: three unmatched edges around a sub-micrometre triangle,
with zero duplicate/degenerate/off-grid triangles. Its exact `post_terrain.water`
snapshot is retained for replay. Tiny-face filtering is being corrected below
the minimum representable area of the existing grid; the audit is not relaxed.

Compiler receipt `reports/retained_artifacts/compiler-cache-20261114T0314.json`
preserves/reconstruction-verifies 227 older derived objects (201,269,225 bytes),
again keeping the newest two per name without changing any storage budget.

Implementation in progress: an immutable bounded local solve precedes wider
relaxation; pending settling no longer suppresses its publication. Background
worker cancellation retains ownership until completion. No timing acceptance
is claimed until the actual gameplay checks pass.

New evidence: `014033888492Z` bounds a local response in a 144,000-cell lake
to 161 cells / three regions and preserves pending wider work. `014623097257Z`
and `015119272487Z` also verify interruption of a real unpublished quantity
change followed by a new authoritative edit. The first integrated attempt,
`014117469038Z`, was rejected: 438 ms lake / 1951 ms sea local response and a
renderer light-unpair diagnostic. `014659390763Z` reaches visible sea-crater
response in 365 ms but fails the 250 ms gate and exposes a background scheduling
deadlock. Its receipt-matched test process was stopped programmatically; no user
process or desktop input was involved. The failed evidence remains retained.

Current changes under test separate urgent edit owners from unrelated ocean
streaming, preserve rollback data for unpublished wider relaxation, permit
background mesh draining while settling remains pending, defer node destruction
to the frame boundary, and account a local snapshot once instead of once per
seed. Actual-game bucket tests include an edit during wider lake relaxation;
they measure click-to-publication, not only native transfer duration.

Latest integrated evidence remains **rejected for terrain latency**:
`015226025367Z` measured bucket scoop/pour 58.824/44.742 ms, but sea/lake/mining
297.752/403.692/454.173 ms. `020000366720Z` and `020206722236Z` retained
the failure; changing staged meshes from layer masks to visibility eliminated
the renderer light-unpair diagnostic in those runs. `020342786322Z` measured
317.722/337.116/321.635 ms and bucket 59.562/58.197 ms. No immediate-terrain
acceptance is claimed. All of these runs used the isolated rendering runner,
normal saved-game barrel placement/projectile damage, and protected source saves.
The mining probe was subsequently corrected to locate the new collision floor
and test newly excavated space, instead of assuming a one-metre-deep cut through
the terrain's interpolated density grid. Subsequent checks must prove that probe.
Remaining optimizations compare consumed occupancy profiles and exact contact
fragments, retire completed edit seeds, and use water-specific edit bounds.

`020916076474Z` first-response two-angle captures revealed a rectangular finite
lake level step: **visual rejection**, even though the sea response was 194 ms.
Those local captures, not later settled pictures, now gate acceptance. The first
taper implementation (`021531819707Z`) was rejected because blending individual
cell fill fractions left air gaps in a deep cut. The replacement tapers column
head and solves its quantity exactly. `021944156627Z` fills both craters and the
normal pickaxe excavation; active-background mesh interruption also passes at
60.510/55.469 ms. Sea/lake/pickaxe latency is 200.881/257.635/291.447 ms, so this
remains unfinished. This run used no captures; the latest column-head transition
still needs visual inspection. Mesh optimization omits buried, unpickable contact
triangulation in runtime buffers; complete closed-volume audits retain contacts.
Native scope/mesh checks `021416428086Z`/`021502801018Z` passed the preceding
candidate and require rerunning after the latest changes.

Compiler cache admission was reached at `020627816429Z` before game launch.
Receipt `reports/retained_artifacts/compiler-cache-20261114T0210.json` preserves
and reconstruction-verifies 179 older derived Zig objects (201,405,698 bytes),
retaining the newest two objects per name before retiring those loose copies.
No storage limit, source asset, save, desktop input or Steam shortcut changed.

Status: ACTIVE, 2026-11-14. The reproduced loading and contact failures now
pass in the source game; performance and final package verification remain
unfinished. Earlier rejected runs are retained below and are not acceptance
evidence for the replacement.

Architecture replacement in progress: the water mesh now extracts the boundary
of clipped occupied volumes directly, subtracts internal faces, and shares edge
vertices across cells/regions. It no longer samples away thin shoreline wedges.
Query geometry uses the same triangles with position-only welding and compact
region-local ownership. Finite discovery gathers existing donors first and uses
a conservative receiving-capacity/connectivity proof to stop watershed growth.
Region-indexed lookup blocks replace per-cell discovery hash allocations, and
interior volume curves are aggregated by elevation during the head solve.

`reports/checks/20261113T222632470888Z` passes actual Cedar_Vale sea/lake paid
barrel placement and handgun explosions, 81 crater probes per shore, terrain-edge
probes within 2 cm, exact lake quantity, and unchanged original save. Both after
angles for both shores were inspected: the previous repeating shoreline notches
are absent. This is scoped visual/functional evidence, not overall completion.
`224511202975Z` loads Hidden_Creek successfully after normalizing small terrain
triangle clipping planes. `225102309377Z` repeats both normal gameplay explosions
with the final exact boundary, all contact/quantity checks passing. Both after
angles were inspected. `225311260236Z` passes actual construction contact and
removal, four probes within 1 cm, and above/underwater visual inspection.

Latest source verification: `20261114T011942739249Z` passes both normal paid
barrel/handgun shoreline cases, 81 crater probes each, shoreline contact within
2 cm, exact finite quantity and original-save hashes. All four after-angle
captures were inspected. `012058910303Z` repeats the formerly failing Hidden_Creek
load successfully. `011426876301Z` passes mining, deposition, object contact,
save recovery and the exact closed-boundary audit (22,694 triangles, zero open,
duplicate, degenerate or off-grid faces). Object, deposition and underwater
mining captures were inspected.

The hidden-tool/handgun animation regression is fixed in `33026e8f`. Moving
gameplay now measures 14.621-15.735 ms frame p95 versus 14.195 ms water-off,
with handgun work 0.343-0.396 ms p95. Timing acceptance remains OPEN:
sea/lake response after terrain publication is 1666/3059 ms, water main p95
0.938/0.761 ms during those blasts, with atomic publication up to 2.293 ms.
Moving residency/retirement still reaches 1.181 ms p95 in the first pass.
These results do not meet the original 250 ms response / 1 ms water-main goals.

The 144,000-cell full lake minus 1 ml and interrupted capture regression passes
`003357265396Z`. Both connected-region selection and COW copying now yield to
the main-thread budget, restart on edits, and retain the unchanged 256 MiB job /
512 MiB aggregate reservations. No water is discarded or budget increased.

## Current repair and acceptance plan

- [x] Reproduce the player's surrounding-ocean explosion and teleport-to-lake
  sequence against the current source and native binaries, using a read-only
  player-world input. Record snapshot admission and region growth.
- [x] Remove whole-world coupling from local equilibrium preparation without
  raising memory limits or dropping water. Test growing ocean residency, local
  edits, interrupted work and fresh saved-world loading.
- [x] Reproduce and close the visible water/object gap. Geometric watertightness
  alone does not pass if water visibly retracts from the solid contact.
- [x] Run actual game barrels, shoreline breaches, mining and deposition with
  rendered before/after/underwater captures on an isolated desktop. Never switch
  the user's desktop or send desktop input. Inspect the resulting images.
- [ ] Attribute response latency, main-thread work, frame tails and repeated
  water-on/off GPU cost; fix measured regressions and retain failed evidence.
- [ ] Verify installed native/source parity, preserve player saves, update the
  issue/index/foundation records and commit the completed, verified work.

Player screenshot on November 13 explicitly reports "Water equilibrium snapshot
exceeds memory budget" after teleporting. Latest gameplay logs also report a
blocked shutdown save with the prior canonical snapshot retained. The former
equilibrium admission retained every resident region plus published occupancy;
prior small-lake checks do not prove growing ocean residency remains supported.
The previously permitted "small contact rims" are not acceptance of the player's
circled object gap.
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

## Surrounding-sea boundary contract (current repair)

Authored inland lakes remain finite and exactly conservative. The surrounding
procedural sea already admits/retires pristine water at fixed sea level; it is
an open reservoir, not a finite lake whose mass ends at the streaming radius.
Terrain edits must prepare native ocean occupancy before changing density, even
outside the player-centered residency square. The worker follows actual clipped
3D connections from pristine sea water through the edited region and records
net reservoir exchange explicitly. Sealed pockets have no sea source and retain
finite quantities. Scooped vacancies are retained. Whole-sea graph traversal is
not an acceptable substitute for this boundary condition.

Local equilibrium snapshots include affected connected groups and their frontier,
not unrelated resident lakes. Existing memory and work limits remain unchanged.
A 4,096-pool regression verifies the scope and untouched distant quantities.

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

## Historical execution gates (superseded by current repair acceptance above)

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


## Performance follow-up after player rejection

The player rejects the current performance. The previous functional verification
is not performance acceptance. Work in progress:

- [ ] Move expensive scene-mesh registration out of atomic publication, preserving
  synchronized render/query updates and bounded staging/retirement.
- [ ] Repeat the identical actual saved-world coast/lake/barrel moving-camera run;
  compare full-sequence publication spikes as well as sampled frame/GPU tails.
- [ ] Inspect rendered contacts and run controlled barrel/terrain/persistence checks.
- [ ] Install the verified change, record measured improvement and remaining limits,
  and commit. Never claim stable 60 FPS from a stationary counter.


## Reopened production failures, November 13

User reports both sea and inland shoreline explosions fail and ordinary loading
reports a connected-body transaction limit. Prior tests forced settling and used
manual detonation; inland checks targeted the lake floor rather than its shoreline.
Those checks are insufficient acceptance. Preserve Steam shortcuts unchanged.

- [ ] Reproduce on the current Cedar_Vale save using normal combat physics/queue,
  no water callback override, and a real shoreline for both water types.
- [ ] Reproduce loading failure from actual saved state and remove its cause without
  discarding finite quantities or silently increasing work/memory limits.
- [ ] Fix the demonstrated interaction and performance failures; repeat rendered
  production-path checks and inspect above/below-water captures.
- [ ] Record final measurements, install matching native/package files and commit.


### Current reproduction evidence

- `reports/checks/20261113T204052189336Z`: Cedar_Vale fails ordinary initial
  loading with the connected-body transaction error. Original save unchanged.
- `20261113T204301763791Z`: diagnostic identifies edited ocean seed
  `(3640,79,3872)`, sea head 40 m, 506 retained regions.
- `20261113T204521509018Z` and `20261113T204914549209Z`: initial boundary
  preparation avoids the immediate error but times out; not accepted.
- `20261113T205224707993Z`: repeated identical 17-region dependency requests
  prove that loaded dependencies were excluded from subsequent local snapshots.
  A retained dependency set now joins the next snapshot and pins required
  streamed ocean regions until commit. Both the failed evidence and original
  memory limits remain. Awaiting actual-game acceptance.
- `20261113T205041509744Z`: mesh-worker ownership, closed query geometry and
  filtering of solid-contact draw faces pass. This is not gameplay acceptance.

### Actual-save investigation, continued

- `20261113T210325155048Z` locates an endless terrain-sample retry at world-edge
  patch `(457,10,499)`. Sampling exactly 2000 m violated TerrainCore's half-open
  domain. The water sampler now requests the interior floating-point limit;
  authoritative contact geometry retains the actual boundary. Four real terrain
  corner regressions pass in `20261113T210547834599Z`.
- Sea restoration must recreate missing reservoir neighbors and retain requested
  dependencies in the next immutable job. Unchanged sea is an interface condition,
  not part of a finite-cell graph. Above-sea quantities now use explicitly
  accounted outlets, preserving sealed/perched finite pockets.
- Rejected attempts remain in `reports/checks`: `211859211943Z`,
  `212102825378Z`, `212251509709Z` still exhausted regional capacity;
  `212443581082Z` exposed a conservation error in the outlet hierarchy, corrected
  before proceeding. Limits were not raised.
- `212557909560Z`: Cedar_Vale initial load, coastal teleport, ordinary paid barrel
  placement/handgun ignition at both sea and inland shorelines, crater occupation,
  and exact inland quantity conservation pass. Initial failing transaction now
  completes in 52 ms on its worker with 75 snapshot regions. Reviewed both
  above-water crater images. This whole run is still FAIL: its obsolete extra
  benchmark combat attempted unsupported placement. The benchmark now measures
  the actual shoreline combat instead of manually advancing detonation.
- Remaining: improve the 5.8 s inland worker discovery; rerun the corrected
  integrated driver, measure frame/GPU tails and inspect captures from cameras
  proven inside water, run final regressions, install matching package and commit.

### Two-angle visual rejection

User requested two angles. `20261113T212942169996Z/player_shore_after_reverse.png`
reveals a vertical water wall and a dry part of the excavation hidden by the
original viewing angle. Reject the earlier visual conclusion. The reservoir
flood discovered dry edited regions but installed quantities only in pending
wet-donor regions. Dry receivers now participate in coastal edit scheduling and
receive water through certified connectivity. Added dry-neighbor coverage
regression and a grid of real crater air samples. Every before/after capture now
has a reverse angle; underwater camera position must pass a volume query.
The failed run also exposed capture-camera state affecting subsequent handgun
aim; captures now restore the prior camera transform before gameplay resumes.
No approval or completion is implied until the corrected integrated run passes.

### Rejected contact quality and remaining finite-load failure

User rejected the saw-tooth lake/terrain contact in the reverse-angle image.
The GPU contact-face filter is removed: classifying one outside endpoint cannot
prove a whole triangle is buried. Restore the identical closed indexed boundary
for rendering and queries. Earlier filtered-GPU timings are historical only.
Do not accept crater interior coverage as proof of a correct shoreline edge.

Hidden_Creek remains a failing actual-save load (`20261113T214945687900Z`).
Sizing the graph from the unchanged 256 MiB reservation passes a 144,000-cell
finite-lake regression (`215315936378Z`), but Hidden_Creek still exceeds its
209,564-cell computed capacity (`215334657689Z`). This is NOT a loading fix.
The remaining solution must reduce finite-body discovery/storage rather than
pretend the failed guard is an acceptable ordinary-world outcome.

Cedar_Vale normal gameplay currently passes crater coverage/conservation in
`214221600776Z`; lake worker reduced to about 1.9 s by revisiting only the
head-dependent frontier. Response and frame-tail targets remain unmet.

### November 14: guards are not accepted gameplay restrictions

- `220245622499Z`: fitting every natural terrain contact caused Cedar_Vale
  boundary preparation to fail. Reject this candidate. The error is a mesh
  worker preparation failure, not evidence that the user's world is invalid.
- `220325524875Z`: phase-specific graph accounting still rejects Hidden_Creek
  at a computed 386,443-cell allowance. The unchanged 256 MiB job reservation
  does not make the all-cells connected-body approach scalable.
- `220704568566Z`: restricting fitting to the natural free-surface intersection
  lets Cedar_Vale load and its ordinary paid barrel/handgun sea explosion finish.
  All 81 interior crater samples pass, but 9 of 23 terrain-edge samples miss
  water within the required 2 cm. Both camera angles were captured; the reverse
  view still shows shoreline notches. Original save unchanged. This entire run
  is FAIL; lake stage was not reached after the sea contact failure.
- Removed the unsuccessful natural-contact fitting experiment. Preserve the
  stronger shoreline test and failed evidence; do not loosen its tolerance.

Next implementation gates: the 0.25 m sampled union can lose thin wet wedges
between terrain and the free surface before vertex fitting runs. Investigate
exact clipped contact-boundary extraction, including shared owner seams and
thin wedges, instead of treating another vertex adjustment as a proven fix.
Connected finite-body work needs compact connected volume/region representation
and incremental invalidation, with exact quantity and spill connectivity tests;
larger cell allowances alone have already failed. Neither direction is complete.
Keep the 250 ms response / 1 ms main-thread / 16.7 ms frame targets unchanged.


### Broader contact topology gate (still active)

`20261113T230245806422Z` passes ordinary terrain mining/deposition, exact quantity,
old-cache migration, unfinished-save loading, and optimized-versus-full occupancy
comparison, but fails the final boundary topology check. Do not infer universal
watertightness from barrel/cube images. The old checker rounded vertices to 1/4096 m
and classified nonzero thin triangles as degenerate. Exact float-coordinate checks
on the retained recovery fixture still find 265 unmatched edges, so this is not
only a test-precision issue (`230714144228Z`). Boundary extraction now shares the
vertices introduced by polygon subtraction as well as original solid vertices;
that correction is being tested. `230703985148Z` was a test-script type-inference
parse failure, corrected before rerunning; it is not a passing game result.


`231432157032Z` closes the retained recovery fixture with exact float-coordinate
edges and zero degenerate triangles. The complete game terrain sequence
`231501612958Z` still fails its final topology gate (37 edges), despite passing
mining, deposition, migration, unfinished-save recovery, quantity conservation,
full-resample equivalence and cube contact. Its 1,479,492-byte `post_terrain.water`
is retained for direct native replay. Canonical projected triangle cancellation
and shared subdivisions at float precision remain under test. Do not treat the
older fixture pass as completion of this newer actual-game case.


### Exact region-local boundary repair

`20261113T235241831622Z` passes the retained full-terrain snapshot: complete mesh,
zero open edges, duplicates, degenerate triangles or off-grid vertices. Coordinates
use a shared 2^-22 m grid in four-metre region-local buffers; the audit preserves
those actual stored coordinates instead of first rounding kilometre-scale world
positions to float. Neighbour clipping vertices share edge subdivisions before
and after projection. Repeated perimeter vertices are preserved until retraced
segments cancel; global vertex deduplication had manufactured thin cap faces.
Numerically equivalent intersections within half a render-grid unit share a
representative. Authoritative integer water quantities are unchanged.

Rejected iterations remain in check reports `234505571001Z`, `234623359098Z`,
`234744638961Z`, `234854468537Z`, `234941700774Z`, and `235138640375Z`.
The full rendered terrain sequence, latest saved-world loading, both normal
barrel shores/two angles, performance targets, and matched export remain open.
The passing native replay alone does not close the plan.


`20261113T235510052357Z` passes the full actual-game terrain sequence including
the strict region-local boundary audit and four 1 cm cube-wall probes. Above-
water deposition/contact and underwater contact captures were inspected.
`235939343074Z` passes paid placement/handgun barrel explosions at both Cedar_Vale
shores, 81 crater probes each, 2 cm shoreline probes, exact lake quantity, and
original-save hash. All four after-angle captures were inspected: the repeating
shoreline notches are absent. `20261114T000100463655Z` loads Hidden_Creek with
unchanged save hash and no capacity/loading error.

Publication now prepares replacement dictionaries before commit and retires old
bookkeeping under the existing frame budget; render-layer swaps avoid costly
visibility notifications. Latest measured lake worker is 297 ms, water main
peak 4.932 ms (equilibrium plus residency in one frame), and whole-game lake
frame p95 29.23 ms. These still FAIL the recorded performance targets.
Active optimization: reuse proven wet-component adjacency, sort only nonzero
integer remainders, invalidate the actual changed cell bounds, cache shared
vertex projection, and avoid mesh preparation in the equilibrium commit frame.
Re-run normal gameplay timing after native regressions. No target or memory
budget has been raised.


`20261114T000646659838Z` passes ordinary sea/lake barrels after reusing wet links
and narrowing invalidation; lake equilibrium worker is 212.050 ms. Main-thread
peak is still 4.085 ms, so performance is not closed. `000822936933Z` repeats the
full terrain/cube sequence successfully. Both Steam desktop links were checked
read-only and remain byte-for-byte identical to their original Steam backups.

Budgeted COW snapshot capture now yields across main-thread slices and restarts
on revision change. Its 144,000-cell interruption regression exposed a separate
fixed-32-iteration head-search error: a full lake minus 1 ml failed quantity
representation (`001208770930Z`, `001333657968Z`). The level search now resolves
under 0.25 ml over the entire connected surface within 48 iterations. The exact
quantity and interrupted-capture case passes in `001602349652Z`. No rounding
loss is accepted and no memory guard was raised.


### Incremental capture and combat attribution, November 14

`003601818736Z` is a rejected diagnostic-script run (incorrect inventory API),
not a game regression. Only its receipt-identified isolated game process was
stopped programmatically; no desktop input or user game process was touched.
Corrected fresh-handgun diagnostic `003712012117Z` passes and measures 0.34–0.42 ms
handgun p95 / 14.93–15.55 ms whole-frame p95. The post-combat 11 ms cost is still
being isolated. Water retirement now shares unused frame budget and ocean
residency admits four regions per gameplay slice (sixteen during loading).
Residency does not retire regions while an incremental snapshot is selecting them.
Final full terrain, failed-save loading and package parity checks remain required.


### Response latency attribution

Handgun visibility restoration is committed as `33026e8f`; `004520102184Z`
passes the hidden-item-to-handgun regression. In actual gameplay
`004300195240Z`, moving-lake water-on p95 is 14.673–15.469 ms, versus 14.087 ms
with water off; handgun p95 is 0.361–0.439 ms. Both ordinary shoreline blasts
and exact water quantities still pass. Capture helpers now restore held-item
visibility as well as camera/process state.

Response is still a failed gate: `004550232066Z` records 1.938 s sea and 4.755 s
lake after terrain publication. The lake solves in 0.223 s but invalidates 1,236
mesh owners and serially prepares about twenty worker groups before publication.
The current optimization skips provably empty mesh owners, caches full-cell
classification, and bypasses polygon subtraction for completely covered faces.
These changes require topology and actual-game verification before acceptance.


`005110310495Z`, `005127251888Z`, `005141928328Z` and `005156302082Z`
pass the retained post-terrain topology, 510-pattern surface continuity, material
contact and worker regressions after the empty/full-face fast paths. Actual
normal gameplay `005309433837Z` still takes 1.717 s sea / 4.590 s lake, so that
optimization is not sufficient. Bounded meshing now tests two native Godot pool
lanes over disjoint owner outputs, immutable shared input and the same memory
reservation (including reserved scratch). Stable serial/parallel geometry and
cancellation must pass before integrated timing acceptance.


The first parallel comparison (`005713258513Z`, `005816361031Z`,
`010012144211Z`) used nine nonadjacent owner regions but stopped after the first
independent publication. It therefore compared one body against all nine. The
fixture now uses contiguous owner regions, so one publication actually exercises
the native group. Those rejected runs remain retained; no concurrency success is
claimed from them.


`010134249114Z` passes stable serial/parallel geometry for one contiguous
nine-owner publication plus cancellation and reservation release. Actual normal
sea/lake gameplay `010313503786Z` passes, with response 1.536 s / 3.206 s. This
remains above the 250 ms target. Further bounded optimizations under test reuse
region-index pointers during wet discovery, avoid full-air inverse-volume calls,
skip fully enclosed air regions, and subtract overlapping rectangular columns
as vertical intervals. General terrain/object clipping remains unchanged.


`010832950499Z`, `010853485839Z`, `010907602741Z`, `010922861960Z`,
`010937551954Z`, and `010952467379Z` pass large/interrupted equilibrium,
ocean equilibrium, exact post-terrain topology, continuity, material/contact,
and parallel mesh-worker regressions after region-index and rectangular-interval
optimizations. A further fast path skips neighbour polygon reconstruction only
when a 3x3 level-air neighbourhood, filled layer below, empty layer above, and
one unsplit top quad prove no shared contact vertices exist. That fast path is
not accepted until topology and the full terrain sequence pass.


### Check-launch isolation correction

The rendered gameplay runs used `--isolated-render` on a private non-input
desktop, but native regressions were mistakenly invoked without `--headless`.
The check runner previously defaulted to fullscreen; those runs must not be
described as desktop-isolated. The omission has been disclosed. The runner now
defaults to headless, requires explicit `--visible-render` for an interactive
window, and makes display modes mutually exclusive. Dry-run checks verified
all four selections without launching a game. All remaining native checks use
explicit headless mode; rendered checks continue on the private desktop. No
Steam shortcut was changed.

### Latest boundary and gameplay evidence

`011426876301Z` passes the full rendered terrain sequence and strict boundary
audit. `011942739249Z` passes normal paid sea/lake barrels, two inspected angles
per shore, and moving water-on/off/on measurements. `012058910303Z` passes
Hidden_Creek loading. The rejected `011546593694Z` never launched: report storage
admission stopped it. Eligible captures were cold-archived with verified receipts
before retrying; limits and original saves were not changed.

Uniform-floor inverse volume now uses its exact linear expression; scope,
continuity, retained topology, materials, mesh workers and ocean checks pass
(`012429612384Z`, `012454562618Z`, `012532846317Z`, `012620480999Z`,
`012647918110Z`, `012705848871Z`). Further latency work caches cell profiles and
heads across overlapping immutable worker halos. Each of two lanes owns at most
8192 entries until the job ends; 8 MiB additional scratch is reserved *inside*
the existing 128 MiB job allowance, reducing available output space. Geometry,
conservation and integrated timing must pass before accepting this optimization.
