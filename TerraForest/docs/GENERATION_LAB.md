# Generation laboratory

First tooling milestone, 2026-11-28. The user accepted the island as a useful
start and requested more authored, interesting geography, inhabited countryside
and town/city planning. They rejected the lakes' arbitrary shapes and reported
missing ground vegetation. This laboratory starts that work; it does not mark
the island, full design vision or 30-second Generate-to-play target complete.

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

`LFP1` version 1 is explicit little-endian data, never a native struct dump.
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

Do not replace saved generator 36 or silently reshape the human playtest world.
Promotion needs an explicit new terrain identity/program storage boundary,
the actual native static-water bake against the same field, edited terrain,
bridge approaches, save/reload and ground-level review. The lab water surface
is a geometric study, not the accepted volumetric-water simulation. A sampled
flood check is not proof against sub-grid leaks.

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
The next return trigger is this first shape/coverage review; implementation of
city planning and populated wilderness remains outstanding. The earlier complete
cold Generate-to-play result remains **80.142 s**, failing the 30-second target.
Cold route planning, scene initialization, landscape loading and map reuse remain
required in parallel with this quality work; do not move work after readiness or
remove content to make the timer pass.

## Storage lifecycle

The driver admits 4 MiB for headless/interactive logs and 8 MiB for captures or
read-only ecology, with zero world allocation. It reuses completed outputs by
source/native/input hash, retains two ordinary completed runs and respects pins.
Only named, hash-matching receipt-owned outputs are archived after process exit;
unknown/later-changed files and all player saves remain protected. Archive limits
are unchanged. Interactive sessions keep their driver alive until the window
closes. Build receipts are under `reports/landform_lab_build_20261128/`.
The three retention tests verify that old receipt-owned output can retire while
pins, modified evidence and unknown files survive. The first inspected candidate
capture is pinned for human shape review; the rejected sea-spill experiment is
cold-retained with reconstruction metadata.
