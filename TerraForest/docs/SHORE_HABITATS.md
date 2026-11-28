# Curved lake fills and native shore habitats

The subsequent [native reuse measurement](COLD_GENERATION_REUSE.md) fixes the
first-play water-map rebuild and reduces the full cold path to 84.627 s, still
above 30 s. This document retains the earlier 99.469 s shoreline baseline and
its separate quality evidence. Current archive capacity is 10.375 GiB following
the explicitly approved cold-path QA increment.

2026-11-28. New ordinary **Inhabited island · living shores** worlds use terrain
38 and LFP1 v3. Earlier terrain IDs and laboratory kernels remain immutable.
Original implementation and tests are AI-assisted 0BSD work; the frozen v2
regression program is original CC0 data. No external assets or dependencies were
added. Existing asset terms remain applicable to gameplay captures.

## Angular margin: physical cause

The terrain-37 inner tip was visibly cut off in the retained lake-2 overview.
The native terrain field itself was curved. A physical-water probe at seed 1703,
2 m spacing and 5 cm below the waterline found **92 missing deep-water points**
inside the lake catalog. These have terrain at least 65 cm below the waterline;
they are not shallow-edge sampling misses.

Catalog sections bound the native half-metre fill job. A horseshoe can have two
arms disconnected *inside one section* although they join in the adjacent
section. The previous single source reached only one of those arms. Terrain 38
clips each compiled guide segment to each section and supplies native fill seeds
for every crossing. They enter the same visited set and physical-contact fill;
there is no new water simulation, mesh overlay, capacity increase or script
sampling loop. Older generators return no extra sources and saved water stays
unchanged.

Reproduction: `reports/checks/20261128T151309422944Z`. Corrected probe:
`reports/checks/20261128T151953784147Z`. The latter finds **zero missing deep-water
points**, zero water on sampled dry terrain, and a rounded physical mask. Red
outside the catalog in these diagnostic images includes the surrounding sea;
the broad `missing_field_points` count is not a leak metric.

The first corrected lake-2 bake uses 43 guide seeds, takes 926.354 ms, stores
27,723,286,176 mL and peaks at 39,216,168 estimated native bytes. The corresponding
legacy probe takes 816.641 ms and omits part of the physical lake. This is a
correctness improvement, not a claimed speedup.

## Terrain and vegetation composition

The shared native v3 field broadens dry bank transitions to 36–84 m and blends
rolling shoulders into existing terrain within 160 m. The existing authored
lake guides remain reusable. Nearby woodland blends into coherent groves and
meadows; laboratory clearings retain priority. The runtime keeps existing
water/slope/road filtering and the fixed 36 candidate trials per 64 m cell.

A 4,624-byte SHR1 program holds 192 endpoint/width records for the three main
lakes. Native scatter builds a spatial index once and persists the program in
GRV2, alongside the existing groves. GRV1 remains readable. The world inspector
validates both formats and exposes guide records through JSON; see
[binary storage](BINARY_WORLD_FORMAT.md#native-shoreline-habitat-records).

The actual island biome test changes 183 cells and leaves **841 of 1,024 cells
identical**. Accepted candidates rise from 7,594 to 7,989; shared IDs, positions,
rotations and scales stay exact. Three complete scatter passes, including the
test's comparisons, take 38.555 ms. Candidate counts precede physical placement
and are not a claim about visible tree counts. Evidence:
`reports/checks/20261128T152239525329Z`. The separate legacy scatter check
`20261128T152309887093Z` passes 576 byte comparisons and eight invalid-input cases.

## Laboratory and physical verification

`reports/generation_lab/20261128T155137033435Z_capture` passes 91 checks. All three
3D views and the winding-valley ecology map were inspected: broader transitions,
rolling surroundings and woodland/meadow variation are present. These are
geometric studies, not populated gameplay or frame-rate qualification. The
257-square native raster costs 56.233–62.311 ms; compilation is 0.144–0.236 ms
for seed 1703 and programs remain 17–20 KB. Older v1/v2 pixels remain exact.
The previous v2 sample was 53–58 ms; no whole-generator speedup follows from
these isolated timings. The first v3 capture `20261128T152150291815Z_capture`
remains as the rejected dry-bank comparison.

`reports/checks/20261128T155255367446Z` passes 87 checks, including 18 legacy
terrain fingerprints, three seeded lake catalogs and the complete seed-1703
physical bake. All 15 sections fill with 201 guide seeds in 3,572.232 ms, retaining
107,984,304,395 mL in 4,775 regions / 98,100,760 expanded bytes. Estimated native
state peaks at 132,542,232 bytes, below the unchanged 128 MiB cap. Exact wet records
and quantities survive dry-cache compaction and restoration, with zero pending
or settling regions after reload. Other seeds have catalog/enclosure checks;
their complete physical worlds are not yet qualified.

## Integrated review and performance

The intermediate ordinary run `reports/inhabited_island_world/20261128T152423859446Z`
passes 128 functional assertions, but was rejected for a dry-bank crease. Its
cold Generate-to-play is **108.162142 s**, including generation, durable publication
and first-play readiness (`plan_cache_hit: false`). Creation has the known
zero-reference shutdown warning; interaction and restoration exit cleanly.
The exact owned fixture is cold in `world.archive.json`, verbose logs in
`logs.archive.json`, and the four lake-0/1 images in `review_captures.archive.json`.
All six views were inspected; the lake-2 witness images remain ready.

The crease came from carrying the nearest guide segment's width across a change
of winner. The corrected dry-bank field uses the continuous minimum signed
distance to the shore. A quarter-metre grid across the reported join has maximum
adjacent height change 0.09259 m and maximum second difference 0.11895 m. The
new native lookup compiles eight-segment bounding groups once, sorts at most
16 fixed stack entries and prunes noncompetitive groups; no heap allocation or
extra objects occur during sampling. It preserves all **309,123** reference
heights byte-for-byte. Sampling the three grids falls from 103.715/108.691/117.171
ms to 71.335/73.269/91.780 ms (22–33% in these focused single-run measurements).
Evidence: `reports/checks/20261128T155026534436Z`, with reference grids restorable
from `20261128T154138471798Z/probe_grids.archive.json`. Wet coverage still has zero
missing deep samples. Full legacy fingerprints and v1/v2 laboratory pixels pass.

The final ordinary run `reports/inhabited_island_world/20261128T155417394546Z`
passes **128 functional assertions**: seven creation, 89 interaction and 32
fresh-process restoration checks. The binary shore program restores exactly;
grass is present at all three shore cameras. All six final shore/overview images,
the lake-2 pre-residency diagnostic and the three final laboratory 3D images were
inspected. The missing arm and dry-bank crease are corrected in these views.
Broad smooth land, simple distant hills and uneven density away from the shore
compositions remain visible. This is scoped improvement, pending human review.

Complete cold-plan Generate-to-play is **99.468834 seconds**, including planning,
generation, durable publication and playable readiness. `plan_cache_hit` is false;
the 30-second target fails. The intermediate 108.162 s run has the earlier field,
so this single-run difference is not a controlled whole-generator speedup claim.
The original terrain-37 run was 94.855 s and omitted physical lake coverage.

| Recorded stage | Seconds |
| --- | ---: |
| Cold terrain/street/site planning | 16.136 |
| Generated scene/terrain initialization | 13.409 |
| Water sources | 4.100 |
| Buildings and interiors | 4.116 |
| Quest-location water contacts | 6.491 |
| Durable world save | 2.242 |
| Waiting for saved map completion | 8.300 |
| First-play landscape coverage | 16.184 |
| First-play map preparation | 10.139 |

These are selected stages, not the complete total. The generation map worker
overlaps saving: its native job takes 10.625 s, including 8.717 s worker time.
`first_play_map_reuse.json` confirms terrain, Blocks and Objects cache hits with
zero terrain patches and zero block/object source calls. **Water misses its
cache**, rebuilding from 1,558 source calls and 321 visibility calls. Investigate
the water revision/cache identity on first play before attempting further map
parallelism. Preserve content and the readiness boundary; do not move that work
after the timer. Planning, initialization, landscape coverage and remaining
script processing stay separate performance work.

Creation exits cleanly. Interaction and restoration each retain the known
zero-reference RefCounted/ObjectDB warning, so strict QA fails despite completed
assertions and zero exit codes. Peak RAM warnings are 4.98 and 4.85 GiB for those
phases. Screenshot HUD rates are not frame-time qualification. Native build
receipts, including initial stale compiler-cache failures and corrected builds,
remain under `reports/shore_habitats_20261128/`; no dependency version changed.

![Corrected horseshoe margin](../reports/inhabited_island_world/20261128T155417394546Z/island_lake_2_overview.png)

Final unedited Godot capture, seed 1703 / terrain 38: the returning inner arm has
a rounded end and the dry-bank join is continuous. Rolling shoulders and grouped
trees are present; the wider smooth terrain and settlement layout still need work.
Compare the retained [terrain-37 angular margin](../issues/world-generator/README.md#historical-terrain-37-shores).

![Ground vegetation along the corrected shore](../reports/inhabited_island_world/20261128T155417394546Z/island_lake_2_shore.png)

Same final run, ordinary ground-cover flags: grass, ferns and trees remain enabled.
These source-game captures use inherited asset terms; they are not generated art
or a claim of sufficient vegetation at every location. Earlier rejected captures
and their restoration manifests remain available rather than being overwritten.

The final owned fixture is cold in `world.archive.json` (60,161,227 loose bytes
retired), and verbose phase logs in `logs.archive.json` (2,637,602 bytes). The
six final lake views and first-play capture remain pinned for human review. The
terrain-37 image set is cold; its two angular-margin witnesses were restored
exactly into `reports/shore_habitats_20261128/legacy_inspection`, with a documented
review pin and `legacy_witnesses.archive.json`. Normal storage admission passes
after retention; temporary report/world limits are restored. The approved
archive cap is 10.25 GiB. See `final_retention.json` in that same evidence folder.
The protected terrain-36 human save retains all 4,059 original file hashes.

Broader terrain/countryside authorship, connected city/town planning, other
complete seeds, human visual approval, clean process exits and the entire cold
path below 30 seconds remain open. The camera fixture now uses the normal native
overview projection input and waits for finished terrain/water render work;
that QA correction is separate from the physical missing-arm fix.
