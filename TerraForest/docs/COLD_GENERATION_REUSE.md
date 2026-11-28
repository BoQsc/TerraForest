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
