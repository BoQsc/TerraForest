# Configurable world creation

Implemented 2026-10-25; expanded 2026-10-28. This is the integrated creation UI and bounded
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
| Ocean coastline | Distributed inland/coastal generator profiles; no alteration to existing saves |
| Build-friendly terrain | Distributed build-friendly profiles 24/25; natural profiles 26/27 when disabled |
| Settlements | One, two or three communities |
| Settlement scale | One, two or three independently terrain-fitted districts per community; three is experimental |
| Regional roads | Direct connections, one alternate route, or an interconnected network with up to one extra link per district |
| Unpaved offroads | None, or up to one/two dirt trails per district, where terrain and crossing grades permit |

The world remains 2 km square. Current recipes produce 12–104 buildings from the
existing catalogue: two expanded communities have 44 buildings; three expanded
communities have 68 across six districts, or 104 across nine experimental districts.
Counts are not silently reduced when a
layout fails. Optional trails/alternate routes are explicitly best-effort, and the
preview reports actual quantities and omissions. Defaults retain two compact
communities, woodland, build-friendly coastal terrain, direct roads and up to one
trail per district. These controls apply only to newly generated worlds.

The 2026-10-28 UI groups settings under World, Landscape and Settlements, with
five starting recipes and Custom mode. Presets set the actual underlying controls;
they do not change the name/seed or independent mineral/grid-fit preferences.
The regional-belt preset selects coastal grassland, three centers, three districts
each, interconnected roads and up to two offroads per district. Its distributed
seed-1703 plan has 104 buildings, 4.30 km of regional links and 5.36 km of trails,
with inhabited districts in all four quadrants. Unsafe optional loops are rejected
and the preview reports the reduced network; no required district is dropped.
This is an experimental connected region, not an approved dense city or new urban
building catalogue. The earlier inland, west-biased preview is retained as history
in the issue tracker, not presented as the current result.

## Distribution and generation cost — 2026-10-28

Previous generation used four lake anchors and clustered town hints. New immutable
terrain IDs 24–27 scatter up to twelve irregular basins over twelve bounded search
tiles, avoiding mine/cave and site reservations. Seeds 0, 42 and 1703 each have
twelve lakes across all four quadrants in every new profile. Distributed bowls use
five-metre maximum depths instead of retaining the old nine-metre small-basin
recipe twelve times; this leaves capacity for player water edits under the existing
finite-volume budgets. An 8×8 bitmask index
keeps ordinary terrain queries from checking every lake. Old terrain IDs and saved
worlds retain their original field, lake locations and edits; this is not migration.

Primary communities use northern/southern/opposite-side search regions. Expanded
multi-town recipes require eastern districts instead of repeatedly accepting all
sites on the western side. Native surveys still enforce 2 m fill / 3 m cut, occupied
envelopes, lake/mine reservations and connected entrances. No building geometry or
trusted destructible plate design changes. The maximum inland seed-1703 recipe
cannot currently fit its required eastern district under these standards; it fails
explicitly rather than silently clustering, shrinking the recipe or raising budgets.
The largest preset uses the validated coastal alternative; custom inland remains
available. Broader seed qualification remains open.

Native routing reuses one bounded regional A* graph per network request, uses exact
segment/rectangle reservation tests, and avoids duplicate generated segments.
Optional links must add meaningful route length rather than retrace an existing
road. Connected grade fitting can reduce optional loop density after bounded
reroutes; it never waives mandatory connectivity or crossing/earthwork limits.

Native map queries skip proven-empty vertical space using terrain heights and
authored-page/block bounds, retaining density checks for edited roofs and caves.
Visibility batches accept 256 candidates but still allow only sixteen expensive
queries per native call. Generation may pipeline up to four map patches through
the existing bounded worker admission; gameplay retains one in flight. These are
algorithm/batching changes, not new per-frame GPU work or relaxed map accuracy.

Water loading reserves the exact validated triangle count per contact cell rather
than geometrically growing every vector. Storage capture excludes regenerable
unmodified ocean cells, while preserving inland water and all edited ocean records,
including empty overrides. Live amounts, contact geometry and rendering are not
changed by capture. The 128 MiB frozen-state and 64 MiB snapshot limits remain;
larger lake counts are not permission for unbounded storage or allocation.

Final package checks retain exact map pixels/visibility in nine baseline cases;
their aggregate visibility work measures 201.188 → 8.451 ms and patch work
267.229 → 5.543 ms. These isolated CPU timings are not total loading or gameplay
speedups. The full new 104-building creation/photo/map/play/save/reload flow passes
42 assertions; creation takes 96.19 s on the current machine. Three twelve-lake
fixtures use 89.7–90.2 MB resident water storage and 48.4–48.9 MB snapshots.
Installed-pack hashes, captures, exact tests and unclosed limits are recorded in
the [world-generator issue](../issues/world-generator/README.md).

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
Its optional alternate routes and wilderness trails use the same bounded native
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

Three-district layouts additionally try four bounded outer site hints when an
inner hint cannot fit. Route reservations honor the same placeholder-site owner
chosen by the lot search; lakes, mines and actual building footprints stay protected.
The larger pipeline admits at most 16,384 grading/mineral commands (still at most
4 MiB of command bytes), 131,072 road-contact footprints (54 MiB of observations),
and 8,192 persisted road segments (still within the 512 KiB navigation envelope).
Native staged terrain residency/checkpoint bounds are unchanged. Generation-only
limits are not runtime streaming budgets or permission to loosen terrain grades.

Sidewalks remain the trusted individually destructible flat plates. Regional
roads and dirt trails remain editable volumetric terrain. No experimental ramp
kit, continuous decorative sidewalk mesh, or diagonal rotated plate is added.

## Storage and caching

`NativeWorldRecipe` stores the authoritative recipe in the compound world section
`world_recipe_v1`: RCP1 little-endian bytes with validated integer fields. Original
five-field recipes remain 28-byte version 1; six-field grid-fit recipes remain
32-byte versions 2–4; seven-field recipes including minerals remain 36-byte version
5. Larger district/network values use 36-byte version 6. Existing valid recipes
retain their exact bytes; the old versions do not accept the new bounds.
Malformed fields fail without mutating live state. Missing sections restore the
legacy biome and do not regenerate any existing world. Opening a save never
applies the currently selected creation controls. Publication validates the exact
requested recipe as well as terrain/building storage. Presentation JSON is only
informational; it is not the source of the live biome setting.

Custom placement plans use `recipe_21_<sha256>.bin`. Keys include seed, terrain
profile, canonical binary options, recipe version, and terrain/structures native
binary fingerprints. The checksummed payload contains plain Godot binary values;
object deserialization is disabled and prefab Resources are rebuilt from recipes.
The successful deterministic placement variant is recorded. Changes to GDScript
recipe geometry/schema require a custom recipe-version bump. The legacy non-custom
plan API remains separate when no custom options are provided. Both plan families
share the 32-entry / 64 MiB derived-cache bound, with a 32 MiB custom-plan limit
and an 8 MiB legacy-plan limit. Writes are staged and verified before rename; trimming
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

2026-10-28 evidence and preserved failed trials: [generator UI and city layouts](../issues/world-generator/README.md).

Still not complete: real city zoning/connected urban grids, substantially broader
building variety, additional climate/asset biomes, and broad ground-level/vehicle
quality acceptance of every district and road approach. The new experimental
three-district option starts city work; complete it with a native district
hierarchy and intersection/entrance contracts; do not label these repeated small
districts as finished cities. Require representative seed/biome captures, real
walking/driving access and long-travel frame-time/memory evidence before promoting
world quality or lower-end performance. The existing WORLD_BUILDING_STANDARD and
NAVIGATION_STANDARD gates remain in force.
