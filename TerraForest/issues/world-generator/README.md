# World generator UI and larger connected regions

- Status: Installed; scoped checks pass. Updated: 2026-10-28.
- User review: New UI and larger layouts not yet reviewed. Existing house approvals stay separate.
- Request: Professional creation UI, controllable towns/cities, connected roads, offroads and biome choices.

## Images

![Regional-belt creation preview](images/regional-belt.png)
Source build, seed 1703, inland grassland, three centers × three districts. Actual
planning preview: 104 buildings, 5.14 km regional roads, 3.99 km trails. Inspected
at 1920×1080; not a ground-level quality approval of all nine districts.

![Settlement controls](images/settlements.png)
Source build, seed 1703, custom two-town/four-district coastal recipe. Settings
are independent controls, not merely names for unchanged generation. Inspected.

![Small-window grid settings](images/landscape-720.png)
1280×720, Landscape tab scrolled to the grouped grid preferences. Inspected for
reachability; controls scroll independently of the live map and generation actions.

## Changes and verification

- Three settings tabs, five editable presets, live actual-plan map and counts.
- Native recipe v6: up to nine districts, interconnected roads, existing offroad/biome controls.
- Bounded outer site search and consistent claimed-site reservations; unchanged cut/fill limits.
- Extended finite generation budgets and binary plan caching; no per-frame planner work.
- Production generation caught false buried-house failures: clearance sampled rounded-down
  lattice points instead of the fractional probe position. It now uses native interpolation.
  The small cellar also declares the same five-metre surface band as its buried shell;
  solid rooms are still rejected, underground walls are not mistaken for filled rooms.
- `reports/checks/20261028T092859632590Z/`: 104-building production data generation,
  6,190 native edits, save/reopen, exact recipe and ore continuity, no cursor capture;
  10 assertions pass. Photos/map rasters deliberately skipped in this fixture.
- `reports/checks/20261028T093027047714Z_generator_ui/`: rendered UI, both resolutions,
  preset/custom propagation, debounce/stale work and largest actual map pass.
- `20261028T091621467943Z`, `20261028T091622465312Z`, `20261028T091624334323Z`:
  native road-contact/collision, staged generation rollback and legacy recipe checks pass.
- `20261028T093308150442Z_city_flow`: full nine-district creation, photo/map baking,
  publication, play, save/reopen and exact approved-building cells pass 42 assertions
  in one OS window. Entire check takes 190.6 s, including travel/reopen/verification;
  it is not a generation-time or gameplay-FPS benchmark. Player worlds stay untouched.
- `20261028T093808352136Z`: all five presets pass 45 native-plan/codec/cache assertions.
  `20261028T093835072262Z`: all 104 building clearance envelopes are clear after baking.
  `20261028T093904660667Z`: 56 C1 geometry, traversal and default-plan assertions pass.
- `20261028094212Z_generator_pack`: packaged 45-option checks, binary navigation
  restore and rendered UI pass with all 14 external DLL hashes matching source.
  Pack SHA-256: `44d31313cb5a082871f4bec4b2fc16ebd8bce70666a6d6a7225ffea90ecb3cad`.
- Release-DLL recipe and road-contact/collision checks pass separately; evidence:
  `reports/world_recipe_native_release.json`, `reports/connected_road_native_release.json`.

## Remaining / resume here

- Current biomes only alter temperate woodland/meadow coverage. Climate materials,
  weather and new asset ecosystems require explicit native/asset work and review.
- Experimental city regions reuse approved buildings. Zoning, a continuous urban
  street plan, architecture variety and all-district access are not accepted yet.
- More seeds, weak-hardware profiling, vehicle traversal and long-play budgets need
  dedicated evidence before claiming universal generation success or city quality.
- The full-flow fixture's `material_map.png` was inspected and shows gameplay,
  not the map (background UI did not open); do not use it as visual map evidence.
  Native map metadata/baking checks and the inspected creation-map images are separate.
- Preserve current player saves. New controls apply to new worlds; do not regenerate old saves.

## Reproduce / retained failures

- Worlds → Create world → Regional belt; seed 1703; Generate & play creates a new slot.
- Headless: `python tools/run_godot_check.py queued_generation --headless --timeout 300 --require "QUEUED_GENERATION checks=10 failures=0" -- --city-generation`.
- Failed initial UI/plan runs remain in `reports/checks/`: `20261028T085659510035Z_generator_ui`
  (small-window layout), `20261028T090030901239Z` (reserved exits),
  `20261028T090257388444Z`, `20261028T090922368468Z` (footprint cap),
  `20261028T091025504385Z` (mineral command cap), `20261028T091318457135Z` (plan cache),
  `20261028T091945984578Z`, `20261028T092702417247Z` (production clearance).
- `20261028T092302754186Z` retains the 42 small-cellar wall probes that exposed
  missing surface-band metadata. Do not count these failures as passes.
- Implementation contract: [WORLD_GENERATION_RECIPES.md](../../docs/WORLD_GENERATION_RECIPES.md).
