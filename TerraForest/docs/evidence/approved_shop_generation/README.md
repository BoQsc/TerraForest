# Approved B2 default and B1 market addition — 2026-10-25

The user explicitly approved B2's roof and had already requested adding B1 to
generation. This integrates both exact designs, without migrating player saves.

## Changes

- B2's 1,028 records and all attached objects are copied exactly into
  `addons/structures/prefabs/village_shop_thin_roof_b2.tres`. Only its name and
  approval metadata differ from the reviewed resource.
- `village_shop()` returns independent instances of that approved prefab;
  `legacy_village_shop()` preserves B0 and historical review authoring/comparisons.
  Existing shop lookup names, native shape geometry and save formats are unchanged.
- Each new market uses one gabled B2 and one hipped B1 instead of two identical
  gabled shops. Other market lots remain unchanged. Neighborhood shops use B2.
  Default generation has two settlements and therefore includes a market; a
  one-settlement/no-market world does not automatically include B1.
- Both derived placement-plan versions advance to 5. The new roof envelopes are
  fitted by the existing native planner, rather than attached to stale fit data.
- The exported PCK is rebuilt. Existing saved buildings and historical review
  assets are not rewritten; A1 remains rejected.

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Exact approved data, independent instances, all eight native market placements | 26 checks, zero failures | `source/` |
| Fresh-process exact market compound restore | 25 checks, zero failures | `restore/` |
| Same approved-data/native-placement test in exported PCK | 26 checks, zero failures | `pack/` |
| Exported startup, 14 external libraries | Passed | `pack/export.log`, `pack/pack_smoke.log` |
| Actual native grading, connected roads and support | 3,852 road probes, zero mismatches; 3,882 foundation samples, zero unsupported | `terrain_fit/` |
| Four custom recipes, cold/warm binary plan caches | Passed | `recipe_cache/` |
| Production UI generation, save and reopen | 11 checks, zero failures; seed 1703, generator 21, six districts | `world_generation/` |
| Independent generated-save load and both physical shop routes | Zero failures; every approved block matches | `populated_walk/` |
| B0/B2 historical comparison | 21 checks, zero failures | `b2_review/` |
| Historical A0/A1 and B0/B1 comparison | 41 checks, zero failures | `historical_comparison/` |
| Approved A2 gameplay/default regression | 32 checks, zero failures | `cottage_regression/` |
| B1 gameplay palette regression | 12 checks, zero failures | `b1_palette/` |

The generated world is an isolated `recipe_generated_*` test slot, not an existing
user save. Publication validates terrain and addon sections together; the UI
returns to the selector, saves and reopens in the same operating-system window.
A second process loads the published snapshot read-only, reconstructs the
deterministic lot plan, and checks every rotated B1/B2 block against actual stored
cells. Its root-save SHA-256 is identical before and after testing.

After destination residency, each route starts on its generated street, walks to
the door, opens it through gameplay E interaction, traverses the customer aisle
and rear stores, and returns to the street without further teleporting. Native
player movement is the only body integrator. Ground cover, settlement actors,
vehicle fleet and normal gameplay construction are enabled. This is representative
shop access, not whole-world NPC pathfinding qualification.

## Terrain and scoped frame observations

| Shop | Grade | Maximum cut | Maximum fill | Frames | Wall p95 | Worst wall frame |
| --- | --- | --- | --- | --- | --- | --- |
| B2, market lot 2 | 36 m | 1.002 m | 0.919 m | 502 | 17.363 ms | 19.710 ms |
| B1, market lot 7 | 34 m | 0.403 m | 0 m | 461 | 17.224 ms | 19.934 ms |

Measured at 1920×1080, 60-FPS cap, Intel i5-12450H / RTX 4050 Laptop GPU.
The metric is elapsed monotonic wall time between process frames, not smoothed
engine delta. Loading and screenshot readback are excluded. There are 35 and 42
resident ground-cover regions at the route endpoints. These short, capped samples
do not prove spare CPU/GPU capacity, uninterrupted 60 FPS, travel streaming
performance or thermal/endurance behavior.

Inspected both final engine screenshots in `images/`: the exact approved roofs
appear in the real vegetated market with supported entrances and connected
approaches. The held tool partially overlaps the overview; clear isolated roof
comparisons remain in the earlier review evidence. Nearby existing landscape and
building-quality issues are not reclassified as accepted by these two images.

## Retained fixture issues

The first fresh-load probe supplied `--temporary` without `--snapshot-readonly`;
it opened a disposable empty world rather than the generated snapshot, and failed
plan reconstruction. `failed_load_fixture/` retains that failure. The corrected
fixture explicitly requires read-only snapshot loading and a durable world recipe.

The next probe proved stored cells and physical access, but lacked the normal
ground-cover/actor/fleet flags. Its `superseded_reduced_systems/` results do not
qualify populated performance. Its early numeric cut/fill fields were missing-key
fallbacks and are **not terrain evidence**. The final test requires the actual
gameplay flags, stores real survey/quality dictionaries and measures wall-clock
frames. The final populated run above supersedes those observations.

## Remaining scope

The B1 generation-hookup and B2 approval gates are closed. Whole-world visual
acceptance, denser scenes, long-distance/endurance performance, arbitrary/shallow
roof pitches and structural collapse remain separate requirements. Earlier
unrelated fixed-count settlement-test failures remain tracked in
`../../WORLD_FOUNDATION_STATUS.md`; this is not a claim that every repository
test is green.

## Reproduce

```text
python tools/run_godot_check.py approved_shop_generation --headless --timeout 90 --require "APPROVED_SHOP_GENERATION checks="
python tools/run_godot_check.py central_market --headless --timeout 180 --require "CENTRAL_MARKET failures=0"
python tools/run_godot_check.py world_recipe_generation --timeout 600 --require "WORLD_RECIPE_GENERATION checks="
python tools/review_modular_buildings.py --shop-roof
```

Exact packed-test and read-only populated-route commands are retained in their
`run.json` files. The route only accepts isolated `recipe_generated_*` slots.
