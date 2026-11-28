# First-play map reuse and native field reuse — 2026-11-28

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
