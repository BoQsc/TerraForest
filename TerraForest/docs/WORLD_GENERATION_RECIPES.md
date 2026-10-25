# Configurable world creation

Implemented 2026-10-25. This is the integrated new-world creation UI and bounded
regional-generation recipe, not approval of finished city or world quality.

## Player workflow

Open `Worlds.cmd`, choose **Create world**, enter a name or leave it blank, and
choose a seed. Landscape and Settlements tabs organize the controls beside a
native-generated map. Preview shows the actual fitted buildings, regional roads,
trails, terrain, water and vegetation field used by generation. Changing a setting
invalidates the preview; a stale worker result cannot replace the current map.
The footer stays available while settings scroll on smaller displays.

| Control | Actual generation effect |
| --- | --- |
| Vegetation biome | Woodland, woodland/meadow mosaic, or open grassland with groves; coherent native tree-admission fields, not a cosmetic map recolor |
| Ocean coastline | Existing coastal/inland generator profiles; no alteration to existing saves |
| Build-friendly terrain | Existing accepted profiles 20/21, with original profiles 17/19 available by opting out |
| Settlements | One, two or three communities |
| Settlement scale | One or two independently terrain-fitted districts per community |
| Regional roads | A connected network; optionally one additional inter-district connection where it fits |
| Unpaved offroads | None, or up to one/two dirt trails per district, where terrain and crossing grades permit |

The world remains 2 km square. Current recipes produce 12–68 buildings from the
existing catalogue: two expanded communities have 44 buildings; three expanded
communities have 68 across six districts. Counts are not silently reduced when a
layout fails. Optional trails/alternate routes are explicitly best-effort, and the
preview reports actual quantities and omissions. Defaults retain two compact
communities, woodland, build-friendly coastal terrain, direct roads and up to one
trail per district. These controls apply only to newly generated worlds.

The biome control changes woodland coverage, not climate, terrain materials or
asset families. It does not claim desert, tundra, tropical vegetation, weather or
new vegetation models. Candidate budgets and IDs stay unchanged; sparse production
density is not globally increased. For seed 1703, the unfiltered native tree
candidate counts are 13,574 / 7,594 / 2,035 respectively. These are whole-field
candidates before slope, water, construction and streaming exclusions, not the
number of loaded trees.

## Native planning and safety

GDScript owns UI, worker dispatch, recipe orchestration and publication. C++ owns
terrain queries, street/lot fitting, A* corridor search, graph connection,
crossing checks, paving plans, biome sampling and map compositing. The main loop
continues while planning. Preview and generation expose actual planning activities
and elapsed time: cache lookup, site fitting, expansion, connection/trails,
navigation validation and raster composition. They do not invent progress inside
a native search.

The regional network joins all districts with distance-ordered feasible links.
Its optional alternate route and wilderness trails use the same bounded native
terrain search. It tries both ends of local streets, not only the south-facing
exits. Different-height centerline crossings and collinear overlaps exceeding
0.25 m are rejected; it does not stamp one incompatible route over another.
Local street curves and regional linear grades are evaluated separately. Corridor
width/shoulder and real walking/driving acceptance remain additional quality gates.

Planning keeps the 2 m fill / 3 m cut budgets and existing terrain grade limits.
If a complete network cannot fit, at most four deterministic district-placement
variants are tried. Expansion districts and the third community are relocated;
budgets are not relaxed and no giant settlement plateau is introduced. A failed
bounded search returns an actionable error before a world is published. The nine
large-layout cases tested include seeds 0, 42 and 1703 with profiles 19, 20 and 21.
Seed 42's build-friendly variants require relocation. Cold planning measured about
1.1–25 seconds across this matrix on the current machine; this is not a universal
generation-time or sustained gameplay-performance guarantee.

Sidewalks remain the trusted individually destructible flat plates. Regional
roads and dirt trails remain editable volumetric terrain. No experimental ramp
kit, continuous decorative sidewalk mesh, or diagonal rotated plate is added.

## Storage and caching

`NativeWorldRecipe` stores the authoritative recipe in the compound world section
`world_recipe_v1`: 28 little-endian bytes, RCP1 magic, schema version 1 and five
validated integer fields (biome, settlements, districts, network, trails).
Malformed fields fail without mutating live state. Missing sections restore the
legacy biome and do not regenerate any existing world. Opening a save never
applies the currently selected creation controls. Publication validates the exact
requested recipe as well as terrain/building storage. Presentation JSON is only
informational; it is not the source of the live biome setting.

Custom placement plans use `recipe_3_<sha256>.bin`. Keys include seed, terrain
profile, canonical binary options, recipe version, and terrain/structures native
binary fingerprints. The checksummed payload contains plain Godot binary values;
object deserialization is disabled and prefab Resources are rebuilt from recipes.
The successful deterministic placement variant is recorded. Changes to GDScript
recipe geometry/schema require a custom recipe-version bump. The legacy version-3
plan API and its original digests remain unchanged when no custom options are
provided. Both plan families share the 32-entry / 64 MiB derived-cache bound, with
an 8 MiB per-plan limit. Writes are staged and verified before rename; trimming
protects the just-written entry and never touches canonical world files.

Preview rasters include the plan digest and relevant native binary fingerprints.
Existing map-layer caches still include native/codec compatibility. In particular,
a source `.gd` codec and exported bytecode deliberately have different fingerprints:
the first cross-build map open can rebuild its derived raster. The packaged
reopen check verifies completion and subsequent hits for terrain, water, buildings
and objects, without modifying the canonical save. `dist/*` is excluded from
export so diagnostic captures in the packaged test directory cannot ship as game
resources.

## Verification and remaining work

Evidence is under `docs/evidence/world_creation_recipes/`. Focused tests cover:

- Binary recipe validation, old-world defaults, native biome determinism and IDs.
- Native road connection determinism and rejection of mismatched crossing grades,
  including a clean isolated release-DLL test.
- Four recipe sizes, cold/warm plan equivalence, nine large-layout seed/profile
  combinations, and the unchanged nine-case legacy plan matrix.
- Actual rendered source/package UI, settings propagation, stale-preview identity,
  on-screen actions at 1920×1080 and 1280×720, and the existing browser tests.
- Full 68-building generation, native publication verification, all six districts
  in the map, same-window play/save/reload, and exact recipe/road metadata restore.
- Pack export/startup, packaged recipe tests, and read-only cold/warm map reopening.

Initial failures are retained in the evidence: a non-ASCII navigation label was
rejected by the native codec (now preflighted before baking); a handoff fixture
returned before the deferred scene transition; small-window actions clipped; and
two large-layout seeds could not connect until bounded relocation was added. The
old two-settlement reopen fixture was also unsuitable for a six-district world
and required an already-warm cross-build cache. The dedicated custom-world test
checks the correct district count and cold-to-warm cache lifecycle instead.

One final-package reopen attempt hit its 180-second outer test deadline after
becoming playable. No root cause was established, and this is not recorded as a
fixed application bug. Progress instrumentation and a 500-second outer deadline
(covering both separately bounded map loads) were added. The subsequent warm
two-load check finished in 24.7 seconds; a deliberately cold terrain-map rebuild
finished in 29.6 seconds including world loading, then its warm reload in 10.3
seconds. All four map layers hit on the second load, and the canonical save hash
remained unchanged. Retain the original timeout and these reruns; reproduce with
the instrumented test and capture queue/worker state if it recurs before claiming
uniform map-load reliability. No production map-cache workaround was added.

Still not complete: real city zoning/connected urban grids, substantially broader
building variety, additional climate/asset biomes, and broad ground-level/vehicle
quality acceptance of every district and road approach. Return to cities after
the present settlement controls/layouts are playtested, with a native district
hierarchy and intersection/entrance contracts; do not label these repeated small
districts as finished cities. Require representative seed/biome captures, real
walking/driving access and long-travel frame-time/memory evidence before promoting
world quality or lower-end performance. The existing WORLD_BUILDING_STANDARD and
NAVIGATION_STANDARD gates remain in force.
