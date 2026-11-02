<!-- SPDX-License-Identifier: CC0-1.0 -->
# World generation, loading and storage audit

2026-11-02. Investigation and proposed architecture, **not a completed performance
rewrite**. New original analysis/data are CC0-1.0; diagnostic code is 0BSD.
Source baseline: `788892f7` plus the shared checkout's existing location-reset
work. That unrelated work was neither changed nor included in this audit's commit.

The largest opportunity is to stop doing whole-world presentation work on the
path to first play. Storage has a second, specific asymmetry: terrain and buildings
already use regional references, but ordinary generated water remains a large
inline snapshot. More threads or a different database alone would leave these
dependencies intact.

## Evidence and limits

[Machine-readable audit](evidence/world_startup_audit/audit.json) and
[reproduction/provenance](evidence/world_startup_audit/README.md) retain the inputs.
These are four recent successful generator-29, seed-1703 runs, not controlled
repetitions of one binary/cache state. The normal Emerald_Meadow world is included.
No user world was written. No new native build, export or full-world benchmark ran
while another chat was changing this checkout. A small lossless-compression
experiment and focused diagnostic regressions were run separately.

| Retained run | Creating phase | Earthworks worker | Water bake | Photograph pipeline | Verification |
| --- | ---: | ---: | ---: | ---: | ---: |
| Quests_1703_202c741e | 81.43 s | 8.02 s | 2.82 s | 24.58 s | 0.897 s |
| Emerald_Meadow | 93.25 s | 8.88 s | 3.10 s | 25.93 s | 0.869 s |
| Quests_1703_796e068b | 70.82 s | 9.38 s | 2.98 s | 24.45 s | 0.876 s |
| Quests_1703_eaa2ed4f | 82.85 s | 8.98 s | 2.76 s | 23.50 s | 0.962 s |

Creating includes earthworks, water and photographs. Do not add these columns as
independent end-to-end phases or treat worker time as exclusive CPU time.
Creating excludes subsequent coordinator verification/publication and entry into
the playable scene. The publication record counts sidecar-store bytes only; it
does **not** include the root archive or preview images.

One previously verified installed-package menu-transition receipt records about
**31.54 s of opening frames**: resource preparation 7.00 s, scene instantiation
0.021 s, setup 2.30 s, then about 22.22 s until the loading barrier clears.
The latter is a residual wall interval, not attribution to a particular subsystem;
workers overlap setup. The largest opening frame was 309.931 ms. This is an
offscreen, warm-cache observation with zombies disabled by that harness, not a
new benchmark or a cold-start guarantee. Source: `reports/menu_transition/20261102T144641939776Z`.

The prior startup work improved responsiveness, but did not establish lower total
loading time. See [the browser issue](../issues/browser-responsiveness/README.md).

## Why the critical path is long

1. **Whole-map readiness gates.** `demo/world.gd` sets `terrain.nearby_first=false`
   and `ecosystem.world_coverage=true`. Terrain loading checks coverage of every
   root, plus the nine local collision probes. Forest readiness requires all
   1,024 owners with no outstanding reconciliation/resampling. Additional readiness
   also requires boulders, every distant building region, world-wide model visuals,
   nearby model rendering, water and local actors. Some work is regional internally,
   but the release barrier is global. Larger worlds will enlarge this barrier.
2. **Generation performs a rendered sightseeing pass.**
   `generate_world_task.gd:bake_photographs` teleports through north/road/market,
   waits for loading and nearby vegetation, then performs image readback/encoding.
   The first view alone waits 16.44–18.42 s for loading. All photos cost 23.50–25.93 s,
   or 28–35% of these creating phases. This is not all avoidable time: some first-view
   work could be reused for first play, but dropping photographs without preserving
   that residency would move work into the next load.
3. **The generator constructs the gameplay scene and later destroys it.**
   It prepares `demo/world.gd` resources, registers services, creates forest/player/UI
   infrastructure, generates authoritative data, renders photographs, saves, caches
   map layers, shuts down and frees the scene. `world_session.gd` then opens another
   world scene after publication. The window persists; scene/native residency does
   not. This creates architectural opportunities for a smaller data builder and an
   explicit handoff of immutable products or selected resident state.
4. **Threaded resource loading is still issued serially.**
   `startup_resources.gd` requests one asset, polls it to completion, retrieves it,
   then advances. Its elapsed budget can add another frame yield after the poll.
   Many recorded resource intervals are approximately 33 ms at 60 FPS. The loader
   avoids one long blocking call but does not pipeline independent assets. Scripts
   still need the established owner-thread grouping; earlier broad threading trials
   leaked resources and must not be repeated blindly.
5. **Baking uses many durable intermediate checkpoints.** These four worlds each
   record 7,007 earthwork commands, 111 checkpoints and 664 region reads. The sample
   terrain directory has 110 packs and 111 indexes. The logged storage worker count
   is one. That counter does not imply that every native operation is single-threaded;
   the existing helper can run bounded parallel batches. Checkpoint frequency,
   overlap, rereads and packing granularity deserve measurement before raising
   thread limits or weakening durability.

## A storage model that is only partly regional

The audited Emerald_Meadow root is **43,170,851 bytes**, of which water is
**42,690,700 bytes (98.89%)**. Terrain is a 40-byte checkpoint reference; structures
are a 2,481-byte reference. Water is a `VRW1` v8 payload. Its `.water` directory has
only a zero-byte lease marker.

This follows the current code: `NativeWaterRegionStore::merge_water_snapshot`
returns the original snapshot when there are no edited/deferred region entries.
Regional water persistence currently addresses edited/deferred ownership; it does
not remove ordinary generated water from the root. The worker validates/restores
water through several layers. That is a candidate for decode-once ownership, but
the audit does not assign an unmeasured number of seconds to those passes.

| Sample storage | Logical bytes | Files |
| --- | ---: | ---: |
| Root plus backup | 86,341,702 | 2 |
| Terrain | 35,115,054 | 222 |
| Model stores | 303,098 | 619 |
| Building regions | 277,576 | 69 |
| Location baselines | 576,638 | 5 |
| Preview photographs | 8,171,648 | 3 |

Total above: 130,785,716 bytes (124.73 MiB), excluding shared derived caches and
reports. File lengths are not allocated disk usage. The model store contains 487
region blobs with median length 245 bytes. Their per-file open/metadata/flush costs
are plausible overhead, not measured attribution. Publication currently copies and
flushes each sidecar file individually before publishing the root.

An in-memory Python zlib experiment reduced the same water bytes to **13.67 MB** at
level 1 or **10.05 MB** at level 6, both byte-exact after decoding. One run took
164/750 ms to compress and 89/109 ms to decode. This only establishes compressibility;
it is not a native codec benchmark, implementation choice or loading-speed result.
Compressing the whole root would still require full decompression and restoration.
The 64 MiB component ceiling is also a structural limit, not a scalable water budget.

## Proposed architecture

```mermaid
flowchart TD
  P[Versioned recipe and global plan] --> B[Immutable regional base products]
  E[Player edits and entity state] --> D[Regional change journal and checkpoints]
  B --> M[Small atomic world manifest]
  D --> M
  M --> L[Spawn and travel priority scheduler]
  L --> N[Nearby authoritative state and collision]
  B --> H[Cached coarse horizon and map products]
  H --> V[Visible background]
  N --> R[Safe first play]
  V --> R
  L --> F[Detailed distant regions as needed]
```

**Separate world data from the scene.** A native world builder should produce the
plan, terrain edits, block/model records, static water and versioned metadata
without constructing the player, menus, renderer or complete gameplay tree.
Keep whole-world planning for connected roads/sites, but materialize spatial
products in bounded jobs. Initial placement and collision acceptance remain
mandatory. Render previews after readiness, at an idle budget, or reuse a cheap
map thumbnail; do not remove approved visible world quality to shorten a timer.

**Make readiness a declared local dependency set.** Require validated root/recipe,
the saved player state, an adequate terrain/building/tree collision envelope, nearby
water interactions and usable departure paths. Include fly-in/waking camera
coverage in the visual envelope. Show a validated coarse horizon immediately;
stream higher detail behind it. Cache distant buildings, vegetation placements and
water surfaces by regional input hashes. Do not merely flip `nearby_first` while
leaving holes or hidden collision dependencies. Travel and teleport admission must
retain explicit unavailable states until their required regions are ready.

**Finish regional storage across components.** Put generated water as well as
edited water in immutable region packs. A root should contain identities, schema
versions and checkpoint references, with small global player/recipe metadata.
Use indexed packs for tiny model records, independent lossless compression per
region/page and bounded read/decode/upload queues. Extend the terrain pack/index
pattern before introducing another unrelated storage protocol.

**Persist changes incrementally.** Keep immutable generated base records and a
versioned journal or copy-on-write regional overlay. Save only changed regions;
compact under byte/time budgets. Atomically publish one manifest generation after
all referenced data are durable. Retain current/backup roots, pins, epochs, exact
checksums and failure recovery. A cross-component edit needs one commit identity;
independently publishing terrain and water can otherwise restore incompatible
versions. Garbage collection must mark from all retained roots/checkpoints and
baselines before reclaiming unreachable blobs. Existing saves require an explicit,
verified migration with their original data preserved.

**Treat generated and derived data differently.** A seed alone is not a save: old
generator and asset revisions must retain their exact realized world. Immutable
base content can be shared by content hash across clones if ownership and reference
tracking are defined. Meshes, collision recipes, map layers and thumbnails are
rebuildable caches keyed by generator/asset/schema and touched-region revisions.
Invalidate affected owners and their dependency halos, not every world product
after a local edit. Bound memory by resident bytes plus queued/captured/upload
bytes, not only by region counts.

**Schedule bounded parallel work.** Use a persistent native worker pool with
priority for spawn/travel/collision and lower priority for distant visuals,
photographs, map layers and compaction. Keep scene-tree/GPU installation on its
owner thread with incremental APIs. Pipeline a measured number of independent
resource requests instead of waiting for each one before issuing the next.
Worker count must respect captured memory and the user's Quiet Mode; no FPS/VSync
or power-setting change is part of this proposal. Godot documents both asynchronous
[resource retrieval](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html)
and the [scene/resource threading constraints](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).

A SQLite-backed regional store is a credible comparison implementation: its
documented application-format advantages include incremental updates and atomic
transactions ([primary reference](https://www.sqlite.org/appfileformat.html)).
Benchmark identical region payloads, random reads, save bursts and crash recovery
against the existing pack/index approach. It would not solve the global readiness
barrier. No database/library is imported or admitted by this audit; any dependency
choice still follows the repository's exact-version provenance rules.

## Implementation order and acceptance

| Priority | Work | Evidence needed before claiming improvement |
| --- | --- | --- |
| 0 | Complete timing attribution | Full trace from Generate/Play through control release; stable stage IDs, queue/wait/CPU/install time, bytes/files, cache outcomes, publication and handoff included |
| 1 | Local first-play contract plus cached horizon | Matched repeated cold/warm source and packaged runs; nearby collision/travel and fly-in intact; no visible holes; first-play time improves, later travel does not regress |
| 2 | Generated-water regional storage and decode-once handoff | Exact quantities/contacts/edits after fresh-process reopen; missing/corrupt-region behavior; bounded resident/peak memory; root size independent of distant water volume |
| 3 | Data-only generation and bounded asset prefetch | Equivalent plan/world digests, same accepted buildings/terrain, cancellation and clean teardown; separate generation, previews, first entry and subsequent load timings |
| 4 | Packed tiny records and incremental checkpoints | Per-phase I/O counters, fewer durable file operations, bounded saves, interrupted publication/recovery, edits spanning components and compaction tests |
| 5 | Parallel generation graph and regional cache reuse | Multiple sizes/seeds and worker budgets; reproducibility, peak memory, p95/worst frame, save time and travel residency under sustained load |

The measured photograph span is an opportunity ceiling, **not a promised 24-second
net saving**. Water compression offers a demonstrated byte reduction, **not a
4x loading claim**. Preserve the existing physical/visual standards and track
first play, total background completion and total generation separately so that
work cannot disappear into an unmeasured later hitch.

## Diagnostic changes completed in this audit

`generation_progress.gd` formerly treated each changing activity label as a timing
stage. Its 64 records filled during asset loading, omitting 83–96% of the elapsed
profile in these four successful runs. Timing schema 2 aggregates stable stage
names, retains revisits, and reports overflow counts/time explicitly. UI activity
text and progress remain unchanged. The isolated regression checks 180 resource
updates, later bake/save stages, revisits, bounded overflow and complete elapsed
accounting. It passes on Godot 4.7.2. Historical missing timing cannot be recovered.

The read-only `tools/audit_world_startup.py` verifies the outer archive checksum,
measures component/file sizes and summarizes retained timings. Six Python tests
cover valid input, corruption, bounds, order/duplicates, missing terrain and
trailing bytes. Native component-schema checks remain with the native codecs.
At the audit checkpoint the diagnostic fix was not yet exported and the larger
changes remained open. The implementation and measurements below supersede that
status; they still do not establish faster startup.

## Local landscape readiness and generated-water packs — 2026-11-03

This first implementation is installed and engineering-verified. **Storage is
smaller; generation/loading wall time has not meaningfully improved.** The
[versioned measurement receipt](evidence/world_startup_optimization/results.json)
records inputs, hashes, timing samples, memory peaks, checks and review scope.
UTC report timestamps are November 2; local completion is November 3.

Normal play requires forest/boulder owners intersecting a 640 m circle around the
player, including pending surface reads and invalidations. Distant owner admission
waits until first play, then resumes through existing bounded queues. Boulders
fill omitted shared-query owners once that individual forest owner is ready,
avoiding duplicate reads and the former global forest barrier. Outside the owner
grid, admission and readiness both fall back to full coverage. Normal generation
photographs retain full coverage. `--whole-landscape-readiness` restores the
previous behavior for diagnosis. Terrain, object horizons, water, actors, map and
nearby collision retain their existing barriers; this is not yet local terrain
or a lazy-water runtime.

The volumetric world remains editable. "Immutable" describes completed files on
disk: edits change live state, and saving publishes new file versions/references
without overwriting the previous checkpoint's dependencies. It does not freeze
water, terrain, or gameplay.

New worlds publish `TFWG` version 1 water references. The root contains the lake
catalog, index identity and a digest of the reconstructed native snapshot. An
immutable `.windex` contains sorted coordinates, pack identity, offsets, compressed
and decoded lengths, and a per-region decoded checksum. Independently Zstandard-
compressed native region records share content-addressed `.wpack` files targeted
at 1 MiB. Regions retain density, quantities, contacts, vacancies and ownership.
The engine supplies compression; no new dependency was imported.

Blobs and index are flushed and verified before the outer compound checkpoint
is published. Existing roots/backups and their referenced blobs remain immutable;
there is no migration or deletion pass. Legacy inline/TFWS worlds retain their
storage family on normal save, and transient edited-ocean receipts retain their
existing protocol. Missing/corrupt dependencies fail loading and disable writes.
The decoder caps 4,096 regions, 64 MiB decoded input, 16 MiB packs and 8 MiB records;
it checks lengths/indices, native records and reconstructed full snapshot identity.

The reader reconstructs the full native snapshot on the worker, preserving current
simulation/rendering behavior. Storage intermediates skip runtime mesh/query
admission and avoid revalidating an already validated per-region catalog. Regional
disk storage does not yet mean bounded water residency or decode-once live handoff.
Changed records currently require recompression and can change the containing
pack's identity. The index supports future independent region admission; that
runtime work remains open.

### Before/after measurements

The ordinary browser recipe used seed 1703, unique `StartupBench_` worlds and
read-only fresh-process reopens. Godot 4.7.2 ran frozen exported packs with debug
native variants at 1920x1080/60 FPS in nonactivating offscreen windows. Existing
OS/shared derived caches were retained: **not a forced cold-cache comparison**.
First-ready excludes intro completion and optional background observation. The
baseline precedes the unrelated quest UI and teardown commits; final artifacts
include them. Treat these as scoped observations, not an isolated causal study.

| Metric | Before | Final |
| --- | ---: | ---: |
| Generate through first-ready, one run | 97.516 s | 100.681 s |
| Load median, three fresh processes | 25.257 s | 25.245 s |
| Load samples | 24.890 / 25.257 / 27.152 s | 26.351 / 24.701 / 25.245 s |
| Water bytes including index/packs | 42,690,700 | 11,388,874 (-73.32%) |
| Whole compound root bytes | 43,170,851 | 481,003 |
| Generation peak private commit | 3.722 GiB | 3.787 GiB |
| Load peak private commit | 3.360 GiB | 3.441 GiB |

The generation difference is +3.2% in a single sample; no generation speedup or
statistically established regression is claimed. Load timing is effectively
unchanged. The lower root size does not establish a total-world RAM improvement.
Final water is an 852-byte reference plus 11,388,022 bytes in 11 packs and one index.
Terrain and structure sections match byte-for-byte. The reconstructed water hash
also matches the baseline exactly. The original Emerald_Meadow root still matches
its audit hash; all readonly reopen fixtures retain their root hashes.

Measured PCK: `465f36fd853330e97a775925df17b78e425bca502cef6cc88db5c949aeb8da83`.
Baseline PCK: `988aa6eb008de18926d33d1c45fe6f423c5d7c3f7f2359ab3c7f844e7bfa7bba`.
Both manifests include 14 matching external DLLs. Final generation receipt:
`reports/startup_optimization/20261102T221520843140Z`; final loads:
`20261102T221046472745Z`, `20261102T221338100942Z`, `20261102T221405838534Z`.
Legacy readonly reopening passed at 24.847 s in `20261102T221705506851Z`.

In the observed final load, all 282 local owners and nearby collision were ready
at release; the other owners completed 7.921 s later. The following 20-second
sample had 18.124 ms p95 and 51.376 ms worst frame time. This is offscreen sampled
behavior, not foreground/high-speed travel qualification. The seated first-play
image and an elevated nearby landscape view were inspected: terrain, nearby
trees, lake and buildings are present. Broader world-quality approval is unchanged.
All final runs passed sampled RAM/VRAM budgets and zero-pointer-capture checks.

### Validation and rejected candidate

Nine focused suites pass in `reports/startup_optimization/qualified_codec/run.json`:
local ownership/admission boundaries and invalidations; real generated-water
byte-exact pack/reopen in debug and release; legacy snapshot compatibility;
generated-water ownership; both-format production load/save failure protection;
streaming save, deferred save and compound checkpoint backup retention. Tests
cover malformed roots, missing indices, corrupt packs, explicit empty catalogs,
repeat publication identity and unchanged source data. Export's building/catalog,
release contract, asset provenance and PCK startup gates passed.

The first candidate merely changed readiness and started boulder work earlier.
It regressed load median to 29.019 s versus its own whole-landscape control at
26.632 s. Its build and all six receipts remain retained. It was corrected by
also deferring distant admission and removing storage-only render preparation;
it is not the final installed build. This finding matters: relaxing a barrier
without reducing competing work does not guarantee faster entry.

Earlier failed diagnostic receipts remain retained: `20261102T211501295041Z`
was stopped due to concurrent world testing; `20261102T212834585528Z` exposed a
benchmark focus-setting reset. Neither is a passing baseline. The harness restores
offscreen mode at handoff. The separate quest check's pre-checkpoint timeout is
tracked with its successful clean repetition in the gameplay-expansion contract;
it is not hidden or attributed to water without evidence.

### Remaining architecture and reproduction

The first audit attributed roughly 14-15 seconds to whole-map terrain coverage
from the displayed stage label. The later sampled readiness trace below corrects
that attribution: water publication remained unfinished after terrain was ready.
Whole-map terrain coverage still requires a valid fallback before its gate can
be removed. Derived-cache accounting and cold-cache behavior remain separate
qualification work.

True regional water residency needs independently validated admission, neighbor/
solver availability, save inheritance of unloaded regions and bounded render
products. Data-only generation and eliminating duplicate scene/resource startup
remain the larger generation tasks. Incremental pack publication/compaction,
cold-cache repetitions, broader seeds, weak-hardware foreground frame times and
sustained travel remain open. Close them with matched repeated timing, memory,
quantity, corruption/interruption and inspected visual/collision evidence; do not
infer completion from this first storage/readiness implementation.

Reproduce with the installed pack using
`python tools/benchmark_world_startup.py --freeze --build reports/startup_optimization/<new-name>`.
Use the reported owned slot with `--slot StartupBench_<id> --repeat 3` to measure
readonly loads; `--observe` records background completion and local collision,
and `--whole-landscape` selects the prior barrier/admission behavior for a load.
`tests/generated_water_packs.gd -- --water-fixture=StartupBench_<legacy-id>` checks
an owned legacy fixture; production failure checks are in
`tests/water_storage_failure.gd`. Do not substitute a user save for test fixtures.

### Paused-focus integration follow-up

A subsequent reset check exposed a mismatch when the player moved while physics
was paused: readiness used the player position but new work used the older
terrain focus. Admission now uses the same player position, preserving the full
640 m requirement. The failing check is retained at
`reports/quests_world/20261102T221830324520Z`; its synchronized-focus repetition
passed 56 + 15 fresh-process checks in `20261102T222352609734Z`.

Integration PCK `aae87e1ffd96d0fbaf9538549f5e05323a269eccad0fba80ebfd725ab5946c81`
contains the center correction and the other chat's trader-list labels. The timing
table intentionally retains the earlier exact measured artifact. A new-format
world passed generation/save/fresh-process reopening (88 + 90 checks) in
`reports/quests_world/20261102T223211692663Z`. Its live trader/reset/cancellation
check deliberately offset terrain focus by 40 m, verified player-centered owner
admission, and passed reset/save/fresh-process reopening (60 + 15 checks) in
`reports/quests_world/20261102T223552833125Z`. Both receipts passed sampled
RAM/VRAM budgets. These are correctness checks, not additional startup samples.


## End-to-end speed follow-up — 2026-11-03

The user's target is one continuous wait: **Generate & play through player
control**, including generation, verified publication, opening, fly-in and waking.
The earlier storage result did not address that target. The speed changes below
keep normal world contents and readiness gates, and add no save migration.

Implemented and exported:

- Keep up to four imported resources loading concurrently, retain dependency order,
  compile scripts on the main thread and drain submitted requests on cancellation.
- During loading, publish up to 16 water mesh packets / 4 ms per call, returning to
  the existing 4 packets / 1 ms gameplay budget afterward. Complete mesh/query
  batches still publish atomically; water quantity and editing are unchanged.
- Pass up to 192 MiB / 512 terrain mesh results from generation to opening within
  the same process. Accept only the exact verified terrain checkpoint and matching
  native/codec/style/meshing signature. Canonical world restoration still runs.
  Edits, checkpoint mismatches and cancellation invalidate reuse; fresh processes
  reconstruct normally. No scene, live world or disk format is retained by this cache.
- Queue up to eight distant-building results / 32 MiB between the native worker
  and main thread. Drain at most four per frame within a 1 ms soft upload slice,
  preserving chunk versions, stale-result rejection and editable block ownership.
- Start map preparation after verified restoration while visual work completes.
  The existing final map readiness/error handling remains in place.

A sampled trace corrected the earlier displayed-stage interpretation: terrain was
ready around 16 seconds into a diagnostic load while water still built until
roughly 27 seconds. After addressing that bottleneck and duplicate terrain work,
serial distant-building delivery and late map preparation became visible. In the
qualified generation, map warming overlaps building reconstruction; both finish
before the final barrier. 233 terrain mesh results were reused in the earlier
handoff candidate; exact hit counts and final queue statistics are in the receipt.

| Timed boundary | Before | Qualified |
| --- | ---: | ---: |
| Generate & play through control | 101.283 s (one run) | 83.911 / 83.176 s; median 83.543 s |
| Generate & play through first-ready | 93.228 s | 75.877 / 75.152 s |
| Normal saved-world reopening through control | 36.664 s | 30.438 s |
| Normal reopening through first-ready | 33.501 s | 27.281 s |

The combined median is 17.740 seconds / 17.5% lower; ordinary reopening is
6.226 seconds / 17.0% lower (one paired sample). These are observed warm-cache
results, not a statistical or universal hardware claim. Both combined repetitions
include the normal eight-second fly-in/waking sequence. All qualified runs pass
sampled RAM/VRAM limits; the observed combined run peaks at 3.732 GiB private commit
and 1.406 GiB dedicated GPU allocation versus 3.714 / 1.403 GiB before. There is
no claimed memory reduction. Reopening has zero process-local terrain handoff hits,
confirming independent reconstruction rather than dependence on generation's cache.

The normal reopening comparison makes a unique full copy of the same owned
generated fixture for each run, with normal map preparation. The source fixture
hash remains unchanged; the disposable copy may checkpoint normal entry state. Older read-only load samples
remain in the evidence but set the session temporary and skip map preparation;
they are **not** substituted for ordinary opening. The first attempted combined
control receipt (20261102T230316965713Z) accidentally triggered entry inside the
generation viewport, consuming waking early. It is retained and excluded. Correct
generation runs require one fly-in, one waking and unblocked player controls.
Ordinary reopening of an already-entered save correctly has no first-entry waking.
Receipt 20261102T233049529346Z failed the initial overly strict test assertions
for waking and root immutability. It changed only its owned benchmark fixture.
Subsequent normal-load runs use independent copies and verify the source hash.

Machine-readable [speed receipts](evidence/world_startup_optimization/speed_results.json)
record exact frozen manifests, driver hashes, run hashes, native checks, save
identities and sampled resource measurements. Before PCK: `7b153c9a...66baac6`;
qualified PCK: `a465003a...89bd801`, with matching external native libraries.
The intervening queue-free handoff candidate took 91.130 seconds through control;
it is retained as an intermediate result, not the installed candidate.

Verification: startup resource/cancellation checks pass; the 64-region water test
needs 50 gameplay publication calls versus 13 loading calls with identical water,
mesh faces and queries, and subsequent editing still works. Fourteen real terrain
handoff checks cover exact arrays/collision recipes, owned columns, incompatible
checkpoints, changed terrain, epochs and limits. Thirty-four building-horizon
checks pass with both debug and release DLLs, including edits, undo, paging,
replacement, disable/re-enable and teardown. Export/catalog/release gates pass.

Generated terrain and structure sections match the before world byte for byte;
the reconstructed water identity also matches. Emerald_Meadow retains its original
root SHA-256 `f6b8f026...20cfa`. The final observed run has full 64/64 terrain roots,
9/9 local collision coverage, local forest/boulder readiness and no map error.
The room and elevated landscape screenshots were inspected: nearby interiors,
terrain, lake, trees and distant buildings are present. This is coverage evidence,
not approval of the existing settlement layout or tool animation. The 20-second
sample **after control** had 17.025 ms p95 / 18.451 ms worst frame time. It does not
qualify foreground responsiveness, high-speed travel or weaker hardware.

The remaining wait is substantial. In one qualified run, generation itself takes
63.725 seconds, including 20.479 seconds of preview photographs, 8.161 seconds of
earthworks, 7.250 seconds placing buildings, 8.106 seconds saving and 6.395 seconds
caching the map. These are observations, not additive estimates for every run.
The next major architectural work is data-only generation and reuse/deferment of
derived preview/map work, with immutable checkpoint ownership, cancellation,
publication and visual checks before changing that pipeline. Regional water
residency, snapshot decode reuse, persistent cache indexing, cold-cache and broader
seed/hardware qualification remain open. Return to these with matched full-control
measurements; the user's reported two-plus-minute case is not reproduced by this
warm-cache seed1703 sample and is not declared solved.

Reproduce the combined metric with `tools/benchmark_world_startup.py --build
reports/startup_optimization/speed_qualified_build --through-control --profile`.
Add `--observe` for post-control collision/image/frame evidence. For normal opening,
add `--slot StartupBench_<owned-id> --normal-load --through-control`. The harness
accepts only owned StartupBench slots and retains receipts; never use a user save.
