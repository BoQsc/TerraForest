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

## Native storage verification

`NativeGeneratedWorldVerifier` replaces the generated-world verification script's
data traversal. The same native entry point serves ordinary publication and the
inspector's `native-check`. It checks recipe/seed/generator identity, every
referenced terrain, structure/model, water and location-baseline checkpoint,
and the root/section hashes. It acquires the existing save lease and rechecks the
root before traversal. It releases stores on success and all failure paths.
This entry point supports current generated regional worlds; it is not a migration
tool for historical inline-only roots, and does not semantically validate every
optional gameplay component. Fresh gameplay restore remains a separate gate.

## Remaining native migration work

The following requirements remain open. Completing this first pass does not
approve the rest as already native, or replace the world-quality/FPS standard.

| Remaining work | Current owner / prerequisite | Evidence required for closure |
| --- | --- | --- |
| Recipe assembly and binary compiled-plan schema | `custom_world_plan.gd`, recipe/catalog factories, `world_generation_plan.gd`; freeze stable authoring schema and immutable loaded asset identities | Native compilation for cold seeds, source/pack identity, corruption rejection, cache invalidation and exact placement/content comparisons |
| Building publication and foundation orchestration | `generate_world_task.gd`, foundation checker; retain existing native prefab atomic transactions and terrain contact contract | Native bounded batch state machine, same cells/attachments/doors, full final-field contact and cancellation checks |
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
