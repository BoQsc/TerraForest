# Cold generation and first-play native reuse — 2026-11-28

## Native first-play publication and corrected control-release timer — 2026-11-28

**72.354259 s cold Generate-to-control, vegetation enabled; the 30 s gate fails.**
The final cold creation is `reports/inhabited_island_world/20261128T195031252970Z`.
Its loading-readiness clock is 69.368398 s, followed by 2.985861 s of the ordinary,
unskipped entry presentation. `controls_released=true`, `entry_enabled=true`
and `plan_cache_hit=false` are recorded. Generation alone takes 46.791466 s.
There is no demonstrated end-to-end speedup in this iteration.

**Measurement correction:** earlier entries on this page called the readiness
clock “Generate-to-play.” That clock stopped while the default entry presentation
still blocked player actions. Historical raw evidence remains unchanged, but all
such earlier values describe Generate-to-readiness, not actual control release.
The test now retains both clocks and asserts the entry/floor-spawn gates have
cleared. It does not skip the presentation or reduce runtime readiness. There is
no measured prior-build control-release baseline for a like-for-like comparison.
“Cold” means a fresh process and absent compiled placement plan, not a reboot or
an empty operating-system/driver cache. These are source-game measurements.

### Native changes and unchanged contracts

- Native model bootstrap keeps unstarted regions separate from admitted reads,
  polls only outstanding tickets and refills freed slots in the same quantum.
  It retains the original two-read window and fixed read-memory reservation.
  The initial-loading allowance is 8,192 records / eight uploads / 3 ms; ordinary
  play keeps 1,024 / two / 1.5 ms. Time quanta are soft limits between calls.
- A never-visible partial draw page waits until full or its collection finishes
  seeding, avoiding repeated uploads of a growing buffer. Already-visible edits
  and removals retain immediate publication. Cancellation, epochs, checkpoint
  leases and the native byte limit remain enforced.
- Native vegetation publication builds transformed bounds and water-root poses
  once per surface result, then merges four exclusion masks in a bounded batch.
  Boulders cache their nine road probes; native code merges their exclusion masks.
  The eight circular offsets use engine-native trig once to preserve exact legacy
  axis rounding. Script scene bridges no longer run those per-object loops.

No density, terrain field, lake shape, coverage radius, collision, canonical save
format or content was reduced. First-play readiness still requires the existing
local coverage; global forest/boulder streaming can continue afterward. The
pipeline is not yet entirely native.

### Measured results

| Boundary | Prior build | Final native visual trial | Final cold control trial |
| --- | ---: | ---: | ---: |
| Generate-to-readiness | 64.241 s | 65.662 s | 69.368 s |
| Generate-to-control | Not measured | Not measured | 72.354 s |
| Generation profile total | 41.093 s | 45.228 s | 46.791 s |
| Planning | 12.129 s | 13.409 s | 14.450 s |
| Generation scene/data initialization | 9.172 s | 12.148 s | 10.342 s |
| First-play loading to readiness | 16.526 s | 13.723 s | 15.100 s |
| First-play landscape stage | 8.595 s | 10.713 s | 11.255 s |
| Separate object-visual tail | 5.250 s | None | None |

Prior evidence is `20261128T182839716684Z`; final-native visual evidence is
`20261128T193337777733Z`, under `reports/inhabited_island_world/`.
The missing separate object tail means work overlapped landscape loading; it
does not mean objects cost zero. Overlapping stages must not be summed into an
alternative total. Single runs vary, and the integrated readiness result regressed.

Both final-native trials publish all 9,480 records in 136 collections / 1,892
pages, with 1,892 uploads and exactly 455,040 transform bytes (48 per record).
There are no pending regions, changes or uploads, and no object-horizon errors.
Charged storage is 19,929,232 bytes within 128 MiB. First play already has canonical
model transforms resident: its zero archive reads are not an archive-I/O speedup.
The visual trial still needs 226 terrain worker builds versus seven generation
mesh handoffs; derived terrain cache records zero hits / 1,658 misses, read-only.
This identifies repeated landscape work that the present change does not remove.
Creation and the same-fixture interaction peak at 4.77 / 4.98 GiB private commit,
respectively, triggering the existing provisional RAM warning. No memory-budget
or whole-frame performance qualification follows from the loading improvement.

### Verification, rejected trials and open gates

The native publication equivalence check passes 75 cases, plus the existing 576
byte comparisons across 72 legacy scatter cases and eight invalid inputs:
`reports/checks/20261128T191412073034Z`. Three earlier failed trig-rounding trials
remain retained (`191038011356Z`, `191149440517Z`, `191248598812Z`, same date).
The correction caches engine-native offsets instead of independently rounded math.

The model-horizon check passes 86 assertions at
`reports/checks/20261128T193028956182Z`, including 100,000 archived records within
64 MiB, 16 regions read exactly once, mutation/removal, exact transforms, and
cancellation/checkpoint cleanup. Its large fixture uses `startup_pressure.archive.json`.
An earlier driver edit overlapped preflight; that receipt is explicitly unqualified
in `preflight_driver_correction.json`. The unchanged-driver repeat and final
86-check result supersede it. Debug/release DLLs are rebuilt from the measured
source; receipts are under `reports/firstplay_loading_20261128/`.

The early six-read / larger-quantum trial (`20261128T191801830217Z`) measured
61.623 s readiness and passed 129 functional assertions, but reproduced the known
zero-reference RefCounted shutdown leak. Its images were not reviewed. That
policy was rejected in favor of the original two-read memory reservation; the
faster early time must not be presented as the final implementation's result.

The final-native visual trial passes all 129 functional assertions (8 / 89 / 32),
but interaction and restoration reproduce that shutdown warning; strict integration
fails. All eight images were inspected: grass, ferns, trees, boulders and water
remain present. Broad plain terrain and repetitive settlement planning remain
unaccepted; sampled image HUDs do not establish whole-world 60 FPS. The visible
entry presentation in the first-play image exposed the timing-boundary defect.

The corrected driver's first attempt failed parsing before generation (explicit
integer annotation corrected); the original cached plan was restored. The final
cold creation passes nine assertions, including control release. Its interaction
launch was rejected by a transient physical-disk reserve failure, not gameplay:
1.53 GiB free versus the unchanged 2 GiB reserve. The original failed receipt is
preserved; the same fixture was rechecked after free space recovered.
No new world was generated for this continuation. `recheck.json` passes all
130 functional assertions (9 create / 89 interaction / 32 restoration). Creation
and restoration exit cleanly; interaction repeats the zero-reference RefCounted
warning, so `passed=false` remains the strict result. The original launch rejection
and source/test identities are preserved alongside the same-fixture recheck.
The transient disk pressure is an additional limit on interpreting this single
latency observation as representative performance.
Complete compiled-plan equivalence passes all four assertions at
`reports/checks/20261128T200341932702Z`: both checksums validate, and the
entire decoded payload matches the prior build after removing only the deliberate
native-library recipe identity and existing observation-time fields.

Remaining performance work is native planning/scene preparation and reuse of
landscape data across generation and first play. Closure requires a complete cold
Generate-to-control result below 30 s, unchanged content/readiness and vegetation,
clean creation/save/reload and broader seed evidence. The intermittent exit leak,
whole-frame performance and human lake/settlement quality approval remain open.
The final receipt at `reports/firstplay_loading_20261128/final_retention.json`
verifies all 4,070 protected human-save file hashes, unchanged measured source/DLLs,
exact restoration of the original compiled plan and successful normal-budget
admission. Only the owned test fixture, its logs and the new measured plan were
cold-retained; manifests preserve every byte. Temporary report/world allowances
have ended, and the archive limit remains 10.375 GiB.


**Partial performance improvement: 84.626608 s cold Generate-to-play. The
30-second requirement remains failed.** The unchanged timer includes the normal
Generate button, cold placement planning, generation, durable publication and
first-play readiness. Vegetation, collision, content and map readiness remain
enabled. This is one source-game comparison, not a post-reboot distribution or
an installed-export claim.

## Changes

The water restore bridge now sets the world's ocean modes before installing its
snapshot. Previously `clear()` created a water owner with both modes disabled;
the first process frame enabled the surrounding ocean and invalidated the saved
snapshot certificate. Correct initialization preserves that certificate. Actual
ocean-mode, water and terrain changes still invalidate derived maps.

Native immutable height queries reuse exact float-coordinate results in a
32,768-entry thread-local direct-mapped table (768 KiB per calling thread).
Configuration identities change on every terrain initialization, including seed
and profile switches. Developed and undeveloped queries have separate keys.
The table adds no approximation, per-query allocation or shared lock. Mutable
voxel edits remain outside it. Sealed native terrain readers also copy the
island ridge and lake-guide arrays that were missing from their field snapshots;
independent cache-disabled contact comparisons cover terrain 36–38.

Native code now canonicalizes prefab metadata and computes planning fingerprints
with the same bytes as the former script implementation. Layout retries retain
their immutable terrain owner, input identity, lake survey and layout. This run
records three input reuses. Verifying a newly written plan compares its exact
checksum/payload bytes rather than decoding and hydrating all prefab assets again.
Loading fills the existing bounded terrain surface-query queue with up to eight
requests instead of the gameplay limit of two; ordinary gameplay retains two.

The overall pipeline is **not yet entirely native**. Recipe assembly, render
resource preparation and parts of scene/stream coordination still require the
migrations listed in [NATIVE_GENERATION.md](NATIVE_GENERATION.md).

## Measured boundaries

Baseline: `reports/inhabited_island_world/20261128T155417394546Z`.
Changed run: `reports/inhabited_island_world/20261128T163050039431Z`.
Both record `plan_cache_hit: false`, seed 1703 and terrain 38.

| Boundary | Baseline | Changed |
| --- | ---: | ---: |
| Complete Generate-to-play | 99.469 s | 84.627 s |
| Full planning stage, including input loading | 16.136 s | 13.195 s |
| Generation scene/data initialization | 13.409 s | 20.717 s |
| Quest-location water-contact wait | 6.491 s | 6.615 s |
| Native saved-map worker | 8.717 s | 1.733 s |
| First-play landscape coverage | 16.184 s | 14.444 s |
| First-play map source/visibility calls | Water: 1,558 / 321 | All layers: 0 / 0 |

These stages overlap in places; do not sum them as an alternate end-to-end timer.
The complete reduction is 14.842 s (14.9%). The changed plan worker alone is
10.676 s, distinct from its 13.195 s full planning stage. Scene initialization
regressed in this run: building-part registration alone took 8.214 s. The measured
map worker improvement does not establish a universal speedup for every stage.

`first_play_map_reuse.json` records certified hits for Water, Blocks and Objects,
with zero rebuild queries or writes. Terrain also hits its saved cache with no
patches. `generate_to_play.json` retains `performance_passed: false`.

## Verification and remaining work

The focused water identity regression, native map raster/cancellation/staleness
regression and island physical/legacy regression pass. The exact native reuse
probe passes 23 assertions, including seed/profile changes, independent sealed
reader comparisons and canonical fingerprint equivalence. An earlier probe
receipt is rejected because its launcher required the wrong summary string;
all 23 assertions passed, and the corrected rerun remains separately recorded.

| Focused check | Passing assertions | Receipt under `reports/checks/` |
| --- | ---: | --- |
| Water restore/cache identity | 14 | `20261128T162352651949Z` |
| Exact native reuse and sealed-reader fields | 23 | `20261128T162829516769Z` |
| Native map raster, cancellation and stale inputs | 28 | `20261128T162854358664Z` |
| Island recipe, legacy fields and lake catalog | 80 | `20261128T162956257734Z` |
| Complete old/new compiled-plan equivalence | 4 | `20261128T164237563208Z` |

The complete plan comparison checks both binary checksums, then all payload
fields after removing only the deliberately changed native-library recipe key
and observation timings. It reports no differences. Native debug/release builds
for terrain and world runtime are source-identity verified; build receipts are
under `reports/cold_generation_20261128/` and the existing native build cache.

Creation, interaction and fresh restoration pass 129 functional assertions
(8 / 89 / 32). All three phases retain the known zero-reference RefCounted exit
warning, so **strict integration remains failed**. The warning is not waived by
diagnostic continuation. First-play and all six lake captures were inspected;
grass, ferns, trees and filled lake arms remain present. Broad smooth terrain,
simple settlement shapes and human visual approval remain open.

The next performance work must address native batching of coarse landscape
reconstruction, render-resource preparation during scene startup, remaining
route-plan assembly and generation-time water-contact settlement. These are
still material costs after the map rebuild is removed; they require separate
immutable-input, cancellation and output-equivalence checks before parallelism
can be enabled. Closure requires the same complete cold timer below 30 s with
clean creation/save/reload, preserved readiness/content and broader seed coverage.
No readiness radius, vegetation setting or measurement boundary was reduced.

The owned fixture and verbose logs use receipt-owned cold retention after the
engine exits. Lake captures use `review_and_logs.archive.json`; first-play uses
`first_play.archive.json`. Captures remain reconstructable through those manifests;
timings, hashes and test receipts remain ready. The maintainer approved temporary
+256 MiB report/world allowances and a permanent 128 MiB archive increment
(10.25 → 10.375 GiB). Normal report/world limits return after the launcher exits.
The protected human save `Island_1703_b743c970` retains all 4,059 original file
hashes. `reports/cold_generation_20261128/final_retention.json` records normal
storage headroom and the three functional assertion counts.


## Startup native batches — 2026-11-28

The follow-up keeps the same terrain profiles, readiness radius, vegetation,
canonical saves and cold timer. It adds:

- Four-lane native reconstruction for consecutive uncached 64 m coarse owners
  during initial loading. Each lane has an independent density/page/block copy
  (at most 256 copied edited pages, existing 32 m halo); the authority performs
  lighting in original owner order. Cache hits are never reconstructed. Missing
  snapshots, invalid inputs and superseded epochs retain the existing serial or
  cancellation path. Interactive terrain work keeps the existing scheduler.
- Native cached-mesh visibility packing and extraction; no per-vertex GDScript
  class/channel conversion remains in this path.
- Native pack vertex/index merging, with existing material support rules,
  source resolution and full-detail geometry retained. LOD generation consumes
  already-read arrays, preserving the packed-normal roundtrip while removing
  its duplicate GPU read.
- Water-contact and mesh invalidation only when construction overlaps an
  existing water region. Receiver surveys still invalidate for all construction;
  actual water intersections retain revision changes and occupancy cancellation.

`region_stages.parallel_columns/parallel_batches` record batch use. Its native
four-stage breakdown covers serial owners only; wall `build_us` includes both.
Generation startup records pack surface-read and LOD counters.

Full cold evidence: `reports/inhabited_island_world/20261128T171853338323Z`,
seed 1703 / terrain 38, `plan_cache_hit=false`. Generate button through the same
playable-world readiness gate measures **70.771693 s**, versus 84.626608 s:
13.854915 s (16.4%) lower, **still failing the 30 s target**.

| Measured stage | Previous run | Native-batch run |
| --- | ---: | ---: |
| Complete cold Generate-to-play | 84.627 s | 70.772 s |
| Generation scene/data initialization | 20.717 s | 14.744 s |
| Building-part registration (inside initialization) | 8.214 s | 4.292 s |
| Quest-location water contacts | 6.615 s | 1.980 s |
| First-play landscape coverage | 14.444 s | 10.386 s |
| Complete first-play loading | 18.365 s | 16.496 s |

The faster landscape stage exposes a 3.530 s world-object visual tail; its 4.058 s
stage reduction must not be presented as the total loading reduction. Planning
still consumes 12.400 s (native/planning worker 10.252 s). All three first-play
map layers retain their fast cache hits, zero source/visibility calls and zero
writes; terrain records zero map patches. These are single complete-run timings,
not a multi-run latency guarantee.

Focused evidence:

- `reports/checks/20261128T171742552937Z`: 216 checks pass. Two seeds (1703, 901),
  terrain 19/36/38, both 4/8 m steps, edited owner seams and clipped world edges.
  All geometry, lighting and collision packets equal the serial path exactly;
  cached visibility equals the old command path; stale/invalid inputs reject.
  Across 24 probes, serial 755.968 ms versus parallel 414.741 ms (1.82x).
- `reports/checks/20261128T171539701772Z`: 238 checks pass. All 110 model render
  buffers and index LODs equal the in-process previous implementation. Bounds,
  collision metadata, unsupported materials, source immutability and unindexed
  input are covered. Headless preparation is 563.869 ms; the graphical full-run
  scene timings above remain the relevant startup evidence.
- `reports/checks/20261128T171329385356Z`: 20 water identity/locality checks pass.
  Dry construction preserves a pending mesh publication and occupancy builder;
  intersecting construction still invalidates water contacts. Edit receiver jobs
  continue using the global building revision, separately from normal occupancy.

Rejected model trial `reports/checks/20261128T171152945132Z` changed 99 packed
normal/LOD outputs. Diagnostic `20261128T171420558437Z` isolated the difference
in-process (its diagnostic-only pass is not an equivalence pass). Removing an
extra renderer conversion changed inputs to LOD generation; the final path
retains that conversion and removes only its duplicate read. The initial trial's
post-run retention also hit normal report admission; the subsequently approved
process-local QA allowance completed receipt-owned retention without deleting
regression evidence.

All six final lake views and first-play were inspected. Grass, ferns, trees and
filled lake arms remain visible. Broad smooth terrain, simple settlements,
transient arrival/collision waits and whole-frame performance remain open; these
captures do not constitute human visual approval or a 60 FPS qualification.

Remaining performance work: remove or reuse more scene/render preparation,
move remaining route assembly into reusable native jobs, and overlap immutable
landscape/object preparation with generation after its final density edit.
The object-visual tail now needs its own bounded native startup scheduling.
These require exact ownership/hash/cancellation and equivalent-output checks;
simply moving the same work into first play cannot close the whole-path target.
Closure still requires the unchanged complete cold timer below 30 s, clean exits,
unchanged content/readiness/vegetation and broader full-seed coverage.


The complete run passes 129 creation/interaction/restoration assertions (8/89/32).
All three phases retain the known zero-reference RefCounted exit warning, so
strict integration remains rejected; diagnostic continuation is not a waiver.
The exact owned fixture is cold-retained (60,146,489 bytes) through
`world.archive.json`. Reviewed lake captures/logs use
`review_and_logs.archive.json`, and first-play uses `first_play.archive.json`.
Normal report/world limits are restored after the approved process-local QA
allowance; the archive limit remains 10.375 GiB. The protected human save is
checked against its original 4,059 hashes in
`reports/startup_native_20261128/retention_and_save_identity.json`.

`metadata_retention.json` records lossless whitespace compaction of five
unpinned world manifests (original bytes remain in adjacent
`manifest_format.archive.json`) and receipt-owned focused-log retention.
`final_retention.json` confirms normal storage admission after QA.


## Planning and startup overlap — 2026-11-28

**Full cold Generate-to-play: 64.240994 s, down from 70.771693 s (9.23%).**
The 30 s gate remains failed. Normal island creation, interaction and fresh-process
restore all pass and exit cleanly in this run, with vegetation enabled. The
placement-plan cache is cold (`plan_cache_hit=false`).
Street-candidate enumeration, exclusion filtering, grading calls and stable ranking
now run as one native batch for the translation-invariant metropolis/island
street templates. Other providers keep their existing contract. A per-core cache
stores exact request/result bytes, capped at 8 MiB/8,192 entries with 64 KiB rows;
terrain revision, immutable field identity and load/reset epoch fence reuse.
Returned dictionaries are independent, including rejected survey results.

Render mesh preparation now advances on the main thread while planning owns its
worker. Source meshes stay read-only; registration reuses the existing native
merge/LOD cache. Character presentation resources join bounded independent
prefetch. Startup forest and boulder publication drains up to eight ready owners
within 2 ms instead of imposing a display frame per one/two owners. Gameplay
limits, vegetation density, support/exclusion rules and readiness gates are
unchanged. No terrain/world format or saved-world version changes.

Verified evidence:

- `reports/checks/20261128T175917399072Z`: 53 native assertions pass across two
  seeds, three terrain versions and both street headings, plus global/boundary,
  caller-mutation, edit/reset invalidation and malformed-input cases. Twelve
  probe totals: old search 233.864 ms, fresh native batch 225.931 ms, reused
  native batch 45.112 ms. The earlier 51-check pass at
  `20261128T175440878013Z` measured 226.760 / 260.280 / 48.620 ms, so fresh-batch
  improvement is not established from these small timings; retry reuse is the
  intended benefit. These are not Generate-to-play measurements.
- `reports/checks/20261128T175815247276Z`: six cooperative render-preparation
  assertions pass, covering cancellation before submission, all pack models,
  source metadata immutability and no repeated native LOD preparation on reuse.
- Debug/release terrain DLLs rebuilt and checked from the current source.
  Startup dependency index and runner syntax checks pass.

Rejected development checks remain visible: `20261128T175258374478Z` exposed
an untyped test Callable; `20261128T175545736680Z` exposed mixed indentation in
the test extension. `20261128T175655163073Z` entered the existing full resource
probe because the new flag branch had not matched a mixed line ending; it
reported 20 assertions but script type errors and an exit leak, so it is not a
pass. The branch and both runtime Boolean declarations are corrected. The final
six-check probe is the bounded branch, not a full startup/cancellation verdict.

Integrated evidence: `reports/inhabited_island_world/20261128T182839716684Z`
and `reports/planning_startup_20261128/comparison.json`. The unchanged timer
covers the Generate button through playable readiness, including durable
publication and first loading. This is one source-game run, seed 1703/terrain 38.

| Measured component | Previous (s) | Current (s) |
| --- | ---: | ---: |
| Complete Generate-to-play | 70.771693 | 64.240994 |
| Generation task, including planning and save | 47.591743 | 41.092699 |
| Planning phase | 12.399742 | 12.129285 |
| Generation scene/data initialization | 14.744166 | 9.172415 |
| First-play scene ready | 3.011517 | 2.927669 |
| First-play loading | 16.495649 | 16.525555 |
| Landscape readiness within loading | 10.385959 | 8.595007 |
| Object-visual readiness within loading | 3.530466 | 5.250300 |

Nested stages must not be added together. All 110 pack models prepare during
planning (6.518 s main-thread work overlapped with the worker); the planning
worker measures 10.012 s. Native street reuse records 3,463 hits/4,811 misses,
2,748 retained entries and 7,718,972 charged bytes at completion. First-play
retains 307 resources, loads resources in 4.078 ms and registers building parts
in 25.167 ms. Water/Blocks/Objects each have one certified fast cache hit with
zero source/visibility queries or writes; terrain has one cache hit and zero
patches. Faster landscape readiness exposes more of the object-visual tail;
first-play total is effectively unchanged in this comparison.

`reports/checks/20261128T183735663488Z` passes four complete-plan comparison
checks: all generated payload bytes are unchanged apart from native-library
identity and observation timings.

All 129 functional checks pass (8 creation, 89 interaction, 32 restore). Unlike
the preceding run, no zero-reference shutdown rejection occurred in any phase.
That earlier intermittent failure is preserved; this run does not establish its
root cause or a universal fix. Private-commit warnings remain about 4.77/4.98/4.88
GiB. All six final lake views, first play and the lake-2 pre-residency view were
inspected: water, grass, ferns, trees and boulders are present. Broad plain terrain,
simple settlements, transient collision-readiness notices and whole-frame FPS
remain open; these captures do not confer human quality approval.

Remaining: the 30 s complete-path requirement, planning/scene CPU work and the
first-play object/landscape tail. Closure needs further native reuse/overlap,
unchanged readiness/content, repeated clean exits and broader cold seed evidence.
No new one-time storage allowance is implied for future iterations.

The approved one-time +256 MiB report/+256 MiB owned-world allowance is complete.
The exact new fixture (60,158,794 bytes) is cold in the run's `world.archive.json`;
reviewed images/logs (17,863,170 bytes) use `review_and_logs.archive.json`. Original
manifest formatting remains losslessly available through
`manifest_format.archive.json`. `reports/planning_startup_20261128/full_check_retention.json`
verifies normal storage limits, all measured DLL hashes and the protected human
save's original 4,059 file hashes. Older focused logs use the three exact receipts
listed in `focused_retention.json`; rejected checks remain recoverable.
