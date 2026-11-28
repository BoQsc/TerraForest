# Native generation and binary world inspection

User direction, 2026-11-27: generation processing belongs in native code, with
compact authoritative world storage and a readable inspector. JSON is an
authoring/inspection interface; it is not the per-cell or per-object runtime.
This is a migration contract. The entire generation pipeline is **not yet
native**, and the existing binary container does not make every component a
fixed-record format.

## Implementation boundary

- Compile authoring inputs once into bounded native records. Use numeric IDs,
  contiguous arrays, explicit versions and shared immutable asset definitions.
- Keep candidate evaluation, spatial queries, sampling, placement decisions,
  hashing, serialization and scheduling out of GDScript processing loops.
- Scene/UI bridges may submit a job, display progress, await completion and
  attach engine-owned resources. They must not perform per-candidate processing.
- Preserve stable candidate/commit order, identifiers, collision/support policy,
  cancellation, stale-revision rejection, recovery and existing saved worlds.
- Parallelize independent work against immutable state. A worker waiting on the
  same mutable owner lock is not parallel throughput. GPU use needs a measured
  suitable workload and an end-to-end benefit including transfers and readback.
- Choose record alignment and indexing for actual throughput. Minimum bit count
  alone is not the goal; compression/decode and memory bandwidth must be measured.

## First converted pass: outdoor objects

`NativeOutdoorGeneration` in `addons/world_runtime/native/outdoor_generation.cpp`
owns candidate generation, RNG order, road/tree/water/reservation filtering,
support probe packing, reply validation and ordered native object insertion.
`addons/structures/outdoor_generation.gd` is now a small scene bridge.

Lots, roads, model bounds and owner identities are decoded once into C++ records.
Roads use a bounded 64 m spatial index with exact narrow-phase predicates; broad
corridors are stored once. Placement diagnostics are materialized at completion.
Model meshes are resolved once per type. Tree candidates are cached by owner cell;
harvest-state queries run only for roots in the candidate footprint. Support
requests retain the existing 4,096-sample bound, 48 attempts and 16 accepted
objects per lot, and 4,096-object world cap. The job yields for asynchronous
queries or a 4 ms owner-thread scheduling quantum between dependent steps.
This is not a hard real-time bound on an individual native call.

Timing separates candidate work, surface waits, filtering, support packing,
density waits and insertion. Wait intervals include queue service/frame delivery,
not just CPU sampling. These counters do not measure GPU time.

The test-only previous implementation is retained in
`tests/fixtures/outdoor_generation_reference.gd`. It is not a production fallback.
Tests compare candidates, exact support samples, complete IDs/transforms and
ordered insertion, cancellation, stale revisions and callback cleanup.

The first ordinary Metropolis trial reduced outdoor placement from 82.565 s to
6.042 s, and recorded creation from 172.605 s to 107.619 s. Counts remained 1,230
objects and 1,156 skips. One of the saved rotations differed by one float ULP;
that trial is **not accepted as exact output equivalence**. The correction uses
the engine's native Basis constructor, avoiding independently compiled math-library
rounding. Corrected verification is recorded below.
The older and new whole-world samples are not a controlled statistical benchmark.

The corrected ordinary run `reports/metropolis_world/20261127T175949980230Z`
records **5.993 s outdoor / 109.224 s total generation**, with all original
outdoor diagnostic fields exactly equal, including all 1,230 IDs/transform bytes.
Of 128 saved root sections, 127 have identical hashes; `location_baselines_v1`
contains the deliberately random per-world identity. Native recipe, terrain,
water, structure/model and gameplay sections all retain their hashes. The
preceding corrected-rotation run was 5.898 / 104.951 s, but failed verification
diagnostics because empty sections used an invalid zero-length hash update.
That error is corrected; the previous results and failures are retained.

Focused evidence: `reports/checks/20261127T173943118904Z` passes 178 placement
checks including 4,024 exact proposals across 84 lots (reference 39.569 s,
native 0.929 s). `20261127T175846717996Z` passes 21 inspector/verification checks.
Eight Python tests pass. The standalone inspector report is
`reports/world_inspector/20261127T175816186530Z/run.json`; source preservation
and component/output comparisons are retained under
`reports/native_generation_inspector_20261127/`. All 2,793 checked content files
of the inspected existing world remain unchanged. Empty lease-control files are
excluded from content hashing. Both native configurations are built from source;
this is source-engine evidence, not an installed/export qualification.

The corrected full workflow passes 6 creation, 73 interaction and 30 fresh-restore
assertions. Creation and restore have clean strict results; interaction reproduces
the inherited zero-reference ObjectDB shutdown warning. The launcher records
`functional_passed: true` and `passed: false`, preserves diagnostic continuation
and cold-retires only its owned fixture. Sampled RAM warnings were 4.18 / 4.55 /
4.35 GiB. This does not close clean-exit, dense-world memory or frame-pacing gates.
Final normal-limit admission, native source/build identity and retirement of
77,733,727 owned fixture bytes are recorded in
`reports/native_generation_inspector_20261127/final_verification.json`.

## Native building validation and publication

`NativeGenerationBuildings` owns the ordinary main-building pass. It copies each
distinct `NativeBlockPrefab` once into a private definition, validates all lots
on a worker against the captured final native terrain revision, then publishes
them in recipe order through the existing atomic native prefab transactions.
The job admits only paused, ready terrain with no pending edit. It bounds the
input to 256 lots and 2,097,152 unique definition cells, pages density queries at
512 samples, and rejects cancellation, changed epochs/revisions and invalid
contact metadata before publishing further lots. Worker code does not access
scene nodes. Definition copies isolate lazy native probe caches from authoring.

Foundation, grading-depth support, interior clearance and exposed surfaces keep
the existing contact contract. Publication keeps original block words, model
IDs/transforms and door-count checks. Cancellation cancels an unpublished
transaction; already committed lots belong to the disposable generation stage,
as before. Owner-thread preparation advances in 8 ms scheduling quanta; a native
commit may exceed that quantum and is measured separately by the maximum advance
counter. This is not a hard real-time guarantee.

Normal generation no longer adds every composed lot to the construction palette,
reconfigures that palette or invalidates editor previews. Explicit editor
qualification keeps its editor route. GDScript submits the job and displays
progress; it no longer loops over probes or building transactions in this pass.
Exploration and sidewalk contact orchestration remain separate migration work.

Focused final-source evidence: `reports/checks/20261127T184200550627Z` passes 68
checks, including exact block/model snapshots across four rotations, shared
definition reuse and source-edit isolation, cancellation, both scene and actual
native-field revision changes, epoch changes and wide-integer admission rejection.
The obsolete queued-generation single-building diagnostic override is removed;
that fixture parses successfully against the new production job. The older C1
fixture now calls the job directly, but its full run
`reports/checks/20261127T184231006804Z` fails 7 of 17 checks **before reaching that
call**: it expects the retired C1 R1 factory/default layout, whereas
`Furniture.large_house()` now returns the expansion catalog and the current
default recipe no longer fits its historical two-settlement assumption. This
failure is retained, not waived. Repair its explicit historical inputs/default
recipe expectations before claiming that old fixture is requalified; preserve
its original reviewed geometry and traversal checks.

The first 4 ms scheduling trial
`reports/metropolis_world/20261127T183156604397Z` passes all 6 creation, 73
interaction and 30 fresh-restore assertions with clean strict exits. It records
7.301 s building-stage / 96.625 s creation, versus 16.730 / 109.224 s before this
pass. Native clone/validation/publication total about 2.635 s; remaining job
wall time includes frame delivery. This motivated the final 8 ms scheduling
quantum. Another vegetation lab overlapped that first trial, so it is not a
controlled throughput benchmark. Creation verifier hashes match 127 of 128
sections; only the deliberately random location-baseline identity differs.
Outdoor diagnostics match except timing counters. Post-interaction roots also
differ in live survival/zombie state; they must not be confused with the
creation-time equivalence check. Evidence is
`reports/generation_building_native_20261127/first_trial.json`.

Final-source ordinary creation, `reports/metropolis_world/20261127T184548795600Z`,
records **6.097 s building stage / 96.088 s creation**. The job publishes 84
buildings and 222,776 cells from 44 private definitions (192,446 definition cells).
It checks 30,485 foundation probes, 30,485 depth-support columns, 552,404 interior
samples and 322,087 exposed-surface samples. Validation takes 0.773 s, definition
copying 0.072 s and owner-thread publication 2.384 s; maximum advance is 12.905 ms.
Final creation hashes again match 127 of 128 sections, with the same random-identity
exception; outdoor differences are timing counters only. See
`reports/generation_building_native_20261127/final_comparison.json`. These are
source-engine observations, not an installed build, a repeated benchmark or
whole-world native completion. The 30-second target remains open.

The final full workflow completes 6 creation, 73 interaction and 30 fresh-restore
assertions. Creation and restore pass strictly; interaction repeats the known
zero-reference ObjectDB shutdown warning, so the launcher correctly records
`functional_passed: true` and `passed: false`. RAM warnings are 4.21 / 4.55 /
4.39 GiB. Neither clean-exit nor dense-world memory/FPS acceptance is closed.
Both native configurations match final source. The first trial's 77,730,951-byte
fixture is cold-retired. Final fixture/capture retirement initially waited for
another game process to exit. Once idle, the same launcher's `--archive-only` and
capture maintenance retired 77,529,967 owned world bytes and the older ordinary
captures, preserving their verified cold archives. Gameplay was not stopped.
Temporary QA limits apply only to the approved child
launcher; normal limits and protected saves remain unchanged. Final storage/build
receipts are retained under `reports/generation_building_native_20261127/`.
The intermediate normal-limit rejection by about 25.4 MiB is retained in
`normal_storage.json`. After archival, normal admission passes: reports 4,043.4
MiB, owned worlds 2,956.7 MiB, archive 9,690.9 MiB and compiler cache 3,755.8 MiB,
all within their unchanged limits. `final_verification.json` records that closure,
both source-matching native builds, the functional/strict distinction and the
separate failed C1 fixture. No storage allowance remains elevated.

## Roads, foundations, map and publication batches (2026-11-28, in progress)

`NativeGenerationEarthworks` compiles the road/foundation command stream,
selects regional road exits and executes bounded foundation/approach surveys,
including the original cut/fill and grade acceptance checks. Offline sign
footings and outdoor objects query the frozen native terrain directly. Mutable
world callers retain their revision-aware queue. Road profiles compute horizontal
geometry once per column; generation checkpoints every 2,048 commands instead
of 64, preserving cancellation, rollback and paged terrain.

`NativeGenerationMaps` captures bounded native scene inputs, then rasterizes
against the unchanged terrain on a worker while the save runs. Its native cache
publisher certifies pixels against the durable root and restored component
identities. Cancellation, changed owners/revisions/transforms, unavailable
regions and incomplete replies reject publication. All four map pixel hashes
match the earlier generator on the full Metropolis fixture.

The first generated root retains complete native structure/model records in
TFSB. Later edited saves retain the ordinary regional format and backup rules.
The inspector and map certificates accept both forms. Model-store publication
uses bounded native workers; portable publication copies and flushes at most
128 paths per batch, joining every worker before the commit journal advances.
No durability or validation step is omitted. Shutdown skips a second save only
when the previous save succeeded and terrain epoch/revision and all captured
addon bytes still match. Dirty, invalid, pending and queued-edit shutdowns keep
the original barriers; 44 async-save assertions cover these cases.

Ordinary run `reports/metropolis_world/20261127T203905800884Z` completed all
109 creation/interaction/fresh-restore assertions. Its creation exit retains
the intermittent zero-reference ObjectDB warning, so **strict acceptance fails**.
It measures **119.416 s Generate-to-play**, including a cold 30.097 s planning
stage, all generation, durable publication and the first playable world load.
The generation stage alone is 70.584 s. Saving takes 1.464 s, the subsequent map
stage 4.414 s and unchanged shutdown finalization 0.152 s. Portable publication
is 0.182 s for 39 files (formerly 3,760), and native verification is 0.920 s.
The earlier cold-plan run `20261127T195756432588Z` measured 134.056 s end to end
and passed all 109 assertions with clean exits. The older 96.088 s number was
only the generation stage with a warm plan; it is not an end-to-end baseline.

The final run `reports/metropolis_world/20261128T103705614198Z` measures
**89.903 s Generate-to-play with a cached placement plan**, including 44.134 s
in generation and 39.174 s in first-play loading. It passes all 109 functional
assertions and preserves the same four map hashes. All three exits retain the
zero-reference warning, so strict acceptance still fails. This is not a cold
timing improvement against the preceding run. Saving is 1.448 s, the remaining
map stage 3.944 s, finalization 0.191 s, portable publication 0.195 s and native
verification 0.918 s. No screenshots were allocated; rendered checks and frame
waits are unchanged.

The source transfers 308 already loaded authoring/script resources across the
scene boundary, with one bounded consumer and explicit cancellation cleanup.
First-play building registration drops from 5.128 s to 21 ms; resource loading
is 5 ms and scene startup 3.349 s. Startup yields after an 8 ms work budget
instead of after every small setup step. The native approach and resource
lifetime regressions pass. The first handoff trial failed because it read the
preparation owner after release; retaining the resources before release fixes
that error, and the final integrated run exercises the correction.

Cold-plan trials compare every serialized field after excluding only the
intentionally changed library fingerprint. The native approach migration passed
that exact comparison in `reports/checks/20261127T205438041344Z`. Additional
height-cache, exclusion-index and connectivity-shortcut trials were rejected:
they preserved output where completed but did not materially reduce the hard
village connection search; the height-cache trial was stopped after regression.
Their logs remain evidence. These experimental terrain-planner changes are not
in the retained implementation.

The **30-second whole-path target remains open**. The remaining work is the
repeated native connection search, generation-scene initialization, first-load
render/collision preparation, remaining script-based planning/placement owners,
and Variant-based placement-plan records. Do not move required work outside the
Generate-to-play timer or weaken site/contact rules to close the target. Closure
requires a cold ordinary UI generation, durable save, unchanged content/map
proof, fresh restore, repeatable clean exits and a measured total below 30 s on
the stated machine. Source timing does not qualify an installed export.

`reports/native_stage_batches_20261127/` retains admission and comparisons.
Earlier storage rejections, malformed test fixtures, an isolated-build include
layout failure, failed resource-handoff trial and the transient checkpoint-pin
retirement assertion remain visible; subsequent passing checks do not erase
those failures. Both configurations of all three changed native libraries match
their current source. Ten launcher tests and startup-index freshness pass.

The final fixture is cold-retained with reconstruction verification. The failed
handoff private stage and two failed/superseded thin native build trials remain
receipt-owned and bounded; archive capacity is nearly full. Their ownership,
preserved upstream notices and archival return trigger are recorded in
`reports/native_stage_batches_20261127/retention_pending.json`. The failed
handoff capture has a documented `.retain` pin. No archive allowance was raised,
and the temporary approved QA report/world allowance ended with its launcher.

## Thirty-second target and reusable pieces

The separate [inhabited island first playtest](INHABITED_ISLAND.md), 2026-11-28,
measures **80.142 s** for its complete cold-plan Generate-to-play path
(`reports/inhabited_island_world/20261128T112502004352Z`). Generation is 49.771 s;
first-play loading is 24.569 s. Cold planning is 7.120 s; generation scene/terrain
initialization 19.686 s, first-play landscape coverage 12.873 s and first-play
map preparation 8.530 s are the next profiling targets. This is a different
recipe/content arrangement, not a same-output speedup over Metropolis.
109 functional assertions pass, strict exit cleanup and the 30-second target
fail. Continue the requested optimization after the first human layout review.

Under 30 seconds is an engineering target, not a proven bound for this world or
for Generate-to-player-control. Record these boundaries separately. The accepted
109.224 s Metropolis creation baseline spends 21.792 s on roads/foundations,
16.730 s on buildings, 16.864 s on save and 18.051 s in the map stage, plus
15.160 s initializing the generation scene. Save plus maps already exceed 30 s.
Language replacement alone cannot close that gap. These are wall-time stages,
including waiting and IO; they must not be described as arithmetic CPU costs.

Locations already use native typed prefab cells, model attachments, frontage and
settlement composition, cached recipe definitions, bulk terrain stamps and
atomic native placement. This is not a scene node or script operation per block.
The current compiled-plan cache still has Variant payloads; full native cold-plan
compilation and an explicit fixed-record schema remain required. Reusing a
definition avoids rebuilding it, but final terrain support and overlap checks
remain necessary for each placement.

Prioritize measured critical-path work: final-terrain query delivery, checkpoint
frequency and region IO during earthworks, generation-only scene preparation,
native population jobs, and save/map scheduling. Save and maps may overlap only
with independent frozen readers and certification against the matching durable
checkpoint. Do not move required work after a timer or weaken player readiness
to claim 30 seconds. GPU compute is a candidate for large independent field work,
not a substitute for removing frame waits, editor refreshes or storage overhead.

## Native storage verification

`NativeGeneratedWorldVerifier` replaces the generated-world verification script's
data traversal. The same native entry point serves ordinary publication and the
inspector's `native-check`. It checks recipe/seed/generator identity, every
referenced terrain, structure/model, water and location-baseline checkpoint,
and the root/section hashes. It acquires the existing save lease and rechecks the
root before traversal. It releases stores on success and all failure paths.
This entry point supports current generated compact and regional worlds; it is
not a migration tool for historical inline-only roots, and does not semantically validate every
optional gameplay component. Fresh gameplay restore remains a separate gate.

## Remaining native migration work

The following requirements remain open. Completing this first pass does not
approve the rest as already native, or replace the world-quality/FPS standard.

| Remaining work | Current owner / prerequisite | Evidence required for closure |
| --- | --- | --- |
| Recipe assembly and binary compiled-plan schema | `custom_world_plan.gd`, recipe/catalog factories, `world_generation_plan.gd`; freeze stable authoring schema and immutable loaded asset identities | Native compilation for cold seeds, source/pack identity, corruption rejection, cache invalidation and exact placement/content comparisons |
| Remaining foundation orchestration | Main-building pass moved to `NativeGenerationBuildings`; exploration and sidewalk callers still use the script foundation bridge | Native bounded jobs for the remaining callers, identical cells/attachments and final-field contact, cancellation and restore checks |
| Resident, parking, lighting, locks and location population passes | Their generation modules; retain reservations and order between populations | Exact IDs, transforms, inventory/quest state and fresh restore for the ordinary recipe |
| Terrain query scheduling and data preparation | Terrain backend/stream bridges around existing native cores; separate frozen readers from mutable caches | No per-sample script loops, revision isolation, bounded memory, cancellation/shutdown and repeated wall-time improvement |
| Save and map publication coordination | `world_persistence.gd`, save/map stage; maintain native durable checkpoint ownership | Native provider/job registry, failure/recovery and matching certified map pixels with whole-save equivalence |
| Remaining Variant-serialized component payloads | Native container can hold opaque bytes; inventory each provider before changing its schema | Explicit per-component versioned fixed records, legacy readers, malformed-input and complete restore coverage |
| Complete inspector coverage | Root/recipe/place schemas and native core companion verification implemented; other gameplay component schemas remain separate | Semantic validation for each remaining schema, bounded portability and complete restore tests |

Return to these entries as each owner is converted. Do not introduce another
GDScript generation loop while extending the pipeline, and do not reduce content,
readiness, support or save durability to improve a timing number.

## World representation and inspector

See [BINARY_WORLD_FORMAT.md](BINARY_WORLD_FORMAT.md). The current root is a native
`TFWORLD1` container; terrain, model, water and baseline companion stores remain
part of a complete saved world. Renaming/copying the root alone is not a portable
world operation. Existing native world clone/publication owns complete transfers.

`tools/world_inspector.py` reads the binary directly, exposes section offsets and
hashes, exports readable metadata, compares sections and supports restricted
place-label edits. JSON edits cannot change generator IDs, seeds, positions,
roads, object IDs or unknown component bytes. The runtime continues loading the
binary container; it never loads the inspector's JSON document.
Recipe JSON is separately exported and compiled into the existing bounded native
recipe bytes for new-world creation. It never rewrites an existing world's terrain.

Original new implementation and tests are 0BSD. No external code, assets or
dependency upgrades are admitted by this migration. Existing Godot/godot-cpp
terms and inventory exceptions remain unchanged.
