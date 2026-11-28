# Generation laboratory

First tooling milestone, 2026-11-28. The user accepted the island as a useful
start and requested more authored, interesting geography, inhabited countryside
and town/city planning. They rejected the lakes' arbitrary shapes and reported
missing ground vegetation. This laboratory starts that work; it does not mark
the island, full design vision or 30-second Generate-to-play target complete.

## Refined shores and island promotion — 2026-11-28

The second laboratory iteration adds asymmetric cove widths, a shallow littoral
shelf, broad versus steep banks, dissected ridges, spurs and saddles, and variable
coastal shelves. The winding composition is the strongest inspected shape study;
branching and crescent compositions provide distinct headlands and approaches.
The renderer remains a field study: its colors are not populated vegetation.

`reports/generation_lab/20261128T123717426482Z_capture` passes 87 checks and
retains inspected views at matched cameras. At seed 1703, compilation is
0.159–0.170 ms and full 257² native sampling/analysis is 53.5–57.7 ms. Programs
are 17,320–19,624 bytes. These richer fields cost more than the first lab kernel;
this is not a generation speedup. The following headless regression
`20261128T124457483606Z_checks` passes 86 checks, including byte-identical pixels
from the retained version-1 program. Previous rejected trials remain retained.

LFP1's header now explicitly selects kernel **1 or 2**. New programs use 2;
old programs retain the original sampling behavior. The independent inspector
reports `kernel_version` and rejects unknown versions. The record layout and
existing size/count limits are unchanged.

The promotion uses immutable native terrain **37**, selected by the ordinary
**Inhabited island · varied shores** recipe. Existing terrain 36 and the protected
human save are unchanged. `assets/island_landforms_v37.json` (under world_runtime)
freezes the promoted original CC0 guide data independently of future laboratory
experiments. `tools/compile_island_landforms.py --check` verifies its generated
native constants. Sampling uses fixed segment records, spatial bins and the same
version-2 lake/ridge/coast primitives as the laboratory. No JSON parsing or
GDScript cell generation was added to the runtime. Future changes to these frozen
fields require a new terrain identity.

The initial native integration check passes 71 assertions across three seeds,
including all 15 old terrain fingerprints and closed physical catalog margins.
At seed 1703 the connected main lakes measure 588 / 534 / 398 m and
18,636 / 27,212 / 16,164 square metres. This is sampled geometry evidence,
not whole-world visual acceptance.

Two rejected full-creation trials are preserved. `20261128T124707709518Z` exposed
road fill exceeding 2 m between grade stations; the native fitter now constrains
terrain at adjacent half-stations too. `20261128T125025163503Z` exposed a coarse
catalog section exceeding the actual 0.5 m water-job volume cap; new sections are
split within that cap. Neither the earthwork policy nor water limits were raised.
The failed staging fixture was receipt-archived. Subsequent native water trials
exposed the resident-state limit at 5 m and 2.8 m basin depths. The selected
production basin is 3.25 m deep, with its water datum rounded down to a 4 m region
boundary. This keeps the deep bed within one region layer while preserving the
promoted horizontal guides and shallow shelf. Dry, unedited sampled regions are
released between completed fill sections; wet quantities and contacts are kept.
The matched control compares every wet region byte and 121 physical depth probes.

The aligned trial `reports/checks/20261128T131008316140Z` completed all 15
sections but failed a stale 64 MiB handoff check. A contact-pruning experiment
(`20261128T131913955141Z`) removed zero contacts and was discarded. Generation 37
now uses the existing 160 MiB expanded-water allowance already supported by the
TFWG compressed region store. The 64 MiB on-disk section limit, 128 MiB bake
state estimate and 8,192-region limit are unchanged. Earlier generation jobs keep
their prior direct-root bound. This is a corrected format boundary, not a new
water simulation or relaxed terrain-contact rule. The live native-state estimate
is not process RAM; full QA records process memory separately.

The test-harness parse failure `20261128T131441770461Z` and compiler-cache
admission failure `20261128T130415203768Z` remain recorded. Exact duplicate
compiler objects were retired only after matching current object hashes under
the build lease (`reports/shoreline_refinement_20261128/compiler_duplicates.json`).
The intermediate native check `reports/checks/20261128T134006757642Z` passes all
80 assertions. Its complete 15-section bake takes 8.852 s and preserves
107,183,157,942 mL through restoration. The 97,213,144-byte expanded snapshot
holds 4,720 wet regions; 160 regenerable dry regions were released. These are
native component measurements, not full creation or frame-rate results.
The integrated trial `reports/inhabited_island_world/20261128T134156275843Z`
then exposed a water-readiness timeout after publication preparation. The focused
probe `20261128T134908927684Z` found 25 settling regions after restore. Replaying
the general settlement path (`20261128T135143021738Z`) reached its existing graph
budget; increasing that budget was rejected as the remedy for initialization.

The cause was contact precision: new fills used double-precision clipped triangles,
while saved contacts were float32. Tiny capacity changes on restore falsely
classified a few authored cells as overfilled. Terrain contact preparation now
rounds triangle coordinates to their existing stored precision *before* assigning
water. Existing saved quantities remain authoritative and are never clamped.
`20261128T135543110648Z` passes 22 focused assertions, including zero pending and
settling regions after restoring the complete bake. The revised initial quantity
is 107,183,157,939 mL (3 mL less than the earlier trial), and is exact on reload.
The final enclosure check also separates adjacent catalog groups at equal water
levels; `20261128T143650734434Z` passes all 22 focused checks with that stronger
gate. The 15-section component bake took 4.396 s in the earlier focused run. Generic whole-lake edit
transactions still retain their bounded graph policy; this is no promise of
arbitrarily large excavation/redistribution.

The later cached-plan trial `20261128T135706924040Z` reached play in 85.449 s,
but its interaction harness incorrectly equated water elevation with lake identity
and selected the wrong region at an exactly aligned waterline. Those tests now
use adjacent physical catalog sections and the submerged region owner. Its old
straight-lake ground camera was underground on curved terrain; new island checks
use actual sampled dry banks. Failed evidence remains cold-retained. The first
cold retry, `20261128T141446226312Z`, exited with native access violation
`0xC0000005` during initial resource loading, before generation. That intermittent
startup defect remains open; a successful retry does not explain or resolve it.

Final complete evidence: `reports/inhabited_island_world/20261128T141848823804Z`.
Ordinary creation, interaction and fresh-process restoration pass **7 + 79 + 30 =
116 functional assertions**, with ground cover enabled and processing. Creation
exits cleanly; interaction and restoration each retain the known zero-reference
ObjectDB shutdown warning. **Strict QA fails.** Diagnostic continuation preserves
those failures. The exact owned fixture is cold-retained in `world.archive.json`;
the protected human save is untouched. The two task-owned placement caches were
held before launch, the report confirms `plan_cache_hit: false`, and both original
cache identities were restored afterward (`cold_plan_retry_hold.json`).

**Complete cold-plan Generate-to-play is 94.855197 s**, including durable
publication and first-play readiness; the 30 s target fails. Major stages include
planning 16.032 s, initial scene/data 21.695 s, water sources 3.202 s, buildings
4.567 s, final location-water contacts 7.852 s, save 2.399 s, saved maps 4.748 s,
and first-play loading 19.654 s (landscape coverage 17.227 s). These are wall-time
stages, not pure arithmetic costs. Peak sampled private commit is 4.63 / 4.90 /
4.80 GiB across the three processes, warning-level results. This richer recipe
is not a controlled speedup over the original 80.142 s terrain-36 baseline.

All six final lake shore/overview captures were inspected. Ground views show
water meeting banks, grass, ferns and trees. Overviews show curved, branching
and crescent outlines, but still plain lowlands, sparse planting in places,
smooth banks and an angular patch at the near end of lake 2. The latter needs a
matched resident-terrain/water diagnostic before it can be attributed to shape,
water publication or overview streaming. It is not accepted shoreline quality.
Screenshots are not frame-time qualification. New tree-density composition,
connected town/city modules and populated countryside remain outstanding.

Final seed-1703 sampled lake areas are 18,632 / 27,188 / 16,136 square metres,
with connected lengths 588 / 534 / 398 m. Only the laboratory's horizontal guide
curves are promoted; production uses the surveyed, region-aligned water datum
and 3.25 m depth described above, not the study's water level/depth parameters.
The physical tests and integrated reload validate this production adaptation;
new human visual approval and broader fitted-world seeds remain required.

## Run and edit

From the project directory:

```text
python -B tools/run_generation_lab.py --interactive
python -B tools/run_generation_lab.py --capture
python -B tools/run_generation_lab.py
python -B tools/landform_inspector.py <retained-program.lfp> --json
```

The interactive window offers three cases, a seed field, native 3D terrain,
terrain map and vegetation coverage views. Right-drag orbits; the wheel zooms.
Edit `addons/world_runtime/assets/landform_library.json`, then use **Reload
modules / build**. Source JSON is authoring data; it is not a generated world.
No new save, project copy or export is needed. Existing saves remain unchanged.

The original CC0 library composes three lake studies from shared original
modules: winding valley, branching basin, and horseshoe lake with an island.
Coast, ridge, woodland belt and meadow modules are reused across these cases.
Keeping them fixed isolates the lake-shape comparison. Seed variation changes
detail within an authored composition; these three studies do not yet establish
creative whole-world variety across seeds.

Each module has a kind and one or more guide paths. Knots are `[x, z, half_width]`
in metres; they are not 3D positions. Instances apply horizontal translation,
rotation and uniform horizontal scale. Heights, water levels and depths remain
explicit. The compiler samples smooth guide curves into bounded segment records
once, then builds spatial bins. The native sampler supplies terrain, water-level
masks, shoreline transitions and potential vegetation coverage from those same
records. Mesh generation, rasterization and basin flood checks are native batches.
GDScript coordinates the window and worker; it does not generate individual cells.

The first kernels are coast, ridge, lake basin, island, woodland belt and meadow
clearing. Branches share one lake feature identity so their basin combines at the
junction. Local width, bank transition, depth and bounded shoreline variation can
be authored independently. Indexing excludes distant features from each sample.
The 3D water mesh is clipped against the sampled terrain instead of covering
shore cells with complete square quads.

## Compact program and limits

`LFP1` versions 1 and 2 use explicit little-endian data, never a native struct dump.
The 32-byte header contains magic, version, seed, float extent, float base height,
float sea level, segment count and a reserved zero word. Each 48-byte segment has
u32 kind and feature ID, then ten float32 fields: start X/Z, end X/Z, start/end
half-width, water/feature level, depth, bank width and variation. An 8-byte
FNV-1a checksum covers all preceding bytes. The checksum detects corruption; it
is not an authenticity mechanism. Both native loading and the independent Python
inspector check bounds and the closed coast chain after checksum verification.

Limits are 32 instances, 512 compiled segments, a 256–2000 m domain, and 513²
raster samples. Interactive geometry is capped at 257² samples. Rejected input
produces no partial program. The first examples use 13,096–14,248 bytes each.
The inspector exports a flat segment view; authoring edits belong in the module
library, whose curves retain their meaning better than edited sampled segments.

## Evidence and rejected experiment

`reports/generation_lab/20261128T120832515868Z_checks` passed the initial 75
numeric checks, but visual inspection rejected the winding lake: it reached the
sea. A bounded declared water mask was insufficient evidence of a closed basin.
That experiment is retained, including through receipt-owned cold archival.

The revised test floods the actual terrain at each lake level and rejects any
lake component that can reach the domain boundary. Basins were moved inward;
no terrain/contact rule was relaxed. The revised capture
`reports/generation_lab/20261128T121320885025Z_capture` passes **87 checks**:
three archetypes at seeds 1703, 901 and 42, exact repeat output, changed seed
detail, corrupted-program rejection, bounded connected lakes, no sampled spill
to the sea, coverage potential and all three interactive mesh previews.
Rendered terrain maps and the 3D views were inspected. They are shape studies,
not approved natural scenery: the ridges still read as smooth ribbons, local
shore detail is limited, and scenery/populated destinations are absent.

At seed 1703, compilation measures **0.149–0.157 ms**; complete 257² native
rasters and analysis measure **43.316–43.469 ms**. The three programs have
1,164 / 1,434 / 1,584 m sampled shoreline. Mesh creation is a separate cost,
shown in the viewer; neither number is Generate-to-play, GPU/FPS performance or
a controlled speedup over the prior world. Debug and release native builds pass
source/output verification. The binary inspector's four malformed/portable-data
tests pass. Native sampling remains bounded CPU work; GPU dispatch is not used.

## Grass regression

The human handoff launcher omitted ordinary gameplay flags, including
`--ground-cover`. `demo/world.gd` enables ground cover from that flag; the ordinary
world browser already supplied it. This was a launcher defect, not an intentional
island design choice. `tools/launch_recipe_playtest.py` now shares one argument
builder with the read-only ecology check and includes ground cover, actors,
vehicles and construction, matching `demo/world_launch.gd`.

```text
python -B tools/run_generation_lab.py --ecology-slot Island_1703_b743c970
```

That check opens the existing protected save read-only, verifies ordinary content
flags and published grass/fern instances, captures a near-ground view and hashes
all existing save companions before/after. It creates no replacement save.
Presence does not establish sufficient tree density or a 60 FPS result. The
laboratory's green/ochre coverage views are proposed vegetation masks, not trees
and grass already planted in a gameplay world.

`reports/generation_lab/20261128T122038255528Z_ecology` passes **11 checks**,
strict exit diagnostics and exact before/after hashes for all save companions.
The inspected near-ground capture shows grass, ferns and trees around the existing
city. Its resident rows contain 80,278 grass and 5,817 fern instances; those are
local population counts, not a density target. Peak sampled private commit gives
a 4.09 GiB warning, below the current hard limit; no FPS/memory acceptance is
claimed. The earlier harness failure (`20261128T121456871965Z_ecology`) used a
nonexistent placeholder slot before scene loading, failed and was stopped; its
source-save hashes also remain unchanged. It is retained as failed evidence.
The existing island can be reopened normally from **My worlds** with these
ordinary content flags; the dedicated handoff launcher still requires matching
native/QA identities and does not waive that guard after native changes.

## Promotion and next tools

Saved generator 36 and the human playtest world remain unchanged. The scoped
promotion above implements the new identity, physical bake, edited-world
contacts, bridge approaches and save/reload gates. Laboratory water alone remains
a geometric study; production uses the real volumetric simulation. Sampled
flood checks are not proof against every sub-grid leak or every future edit.

Next bounded modules should cover:

- Lake margins and countryside: shore shelves, rocky coves, wet/meadow/woodland
  transitions, groves and authored clearings with useful landmarks and paths.
  Add detail through reusable compositions and instanced assets, not arbitrary
  noise or unbounded object scatter.
- City and town structure: reusable street graphs, entrances/connection ports,
  block/frontage envelopes, squares, green space and distinct land-use palettes.
  Fit the connected districts together before placing the existing approved
  buildings. Preserve the 2 m fill / 3 m cut policy and usable entrances.
- Regional organization: reserve drainage, coast access and bridge corridors
  before settlements; then join useful destinations and measure route coverage,
  empty spans, terrain fit and repetition. Isolated street strips are not a city.

Each addition must join this same laboratory with an authored intent, baseline,
matched views, geometry/connection checks, native cost and a promotion gate.
The next return trigger is human review of the promoted shore views and a matched
diagnostic of the angular lake-2 margin. City planning and populated wilderness
remain outstanding. Latest complete cold Generate-to-play is **94.855 s**,
failing the 30-second target.
Cold route planning, scene initialization, landscape loading and map reuse remain
required in parallel with this quality work; do not move work after readiness or
remove content to make the timer pass.

## Storage lifecycle

The driver admits 4 MiB for headless/interactive logs and 8 MiB for captures or
read-only ecology, with zero world allocation. It reuses completed outputs by
source/native/input hash, retains two ordinary completed runs and respects pins.
Only named, hash-matching receipt-owned outputs are archived after process exit;
unknown/later-changed files and all player saves remain protected.
The maintainer approved a 128 MiB archive increase on 2026-11-28, from
10 GiB to 10.125 GiB, after retention reached its limit. Report/world QA headroom
is process-local and restores the normal limits at exit. Interactive sessions
keep their driver alive until the window
closes. Build receipts are under `reports/landform_lab_build_20261128/`.
The three retention tests verify that old receipt-owned output can retire while
pins, modified evidence and unknown files survive. The first inspected candidate
capture is pinned for human shape review; the rejected sea-spill experiment is
cold-retained with reconstruction metadata.
