# Developer UI separation — 2026-10-25

See `../../PLAYER_UI.md` for the UI, inventory and population compatibility contract.
All rendered world fixtures used temporary worlds and unique disposable slots;
no existing player save was opened or rewritten. No navigation behavior or actor
runtime limit is relaxed by this change.

## Checks

- `catalog_ui/`: 19 real-world assertions for separate pages, all 36 item grants,
  baked icons, text/category search, typing M/tilde without hotkey leakage, exact
  quantity, full-inventory atomicity, actual zombie spawning, native identity,
  saved wounds/reactivation, unloaded ground rejection and ESC cursor ownership.
- `vehicle/`: seven assertions, including first-click live vehicle spawning while
  looking at the sky and ordinary interaction gates are unavailable, plus a
  separate carried vehicle item grant with no duplicate live car.
- `belt/`: existing development-belt/Alt ownership regression, updated navigation.
- `gameplay_items/`: existing repair, terrain placement, vehicle radial/inventory,
  durability/storage and redeployment checks with the new bag workflow.
- `population/`: 33 native checks, including legacy bytes, extended records,
  malformed restore atomicity, native indexing and the 256-addition bound.
- `fresh_population/`: four fresh-process disk-read checks for extended population,
  including original deaths and added-resident injuries.
- `population_world/`: 15 actual-world residency/restore/travel checks.
- `zombie_population_release.*`: isolated release-library native checks.
- `pack/`: current packaged native population, rendered UI/spawn and vehicle tests;
  manifest records the exact tested PCK SHA-256. `export.log` retains startup check.
- `images/`: inspected actual packaged Dev Bag, Dev Spawner, Developer and spawned
  zombie captures, not mockups. `artifact_hashes.json` matches changed source DLLs
  to the shipped copies.

## Initial fixture failures

`initial_soil_fixture/` retains two failed terrain/payment assertions: the older
fixture disabled its game physics loop and clicked immediately after changing aim,
before the asynchronous native target existed. It now explicitly waits for a valid
native target before that click; both original edit/payment assertions remain.
No production terrain code was changed. The full corrected item test passes.

`initial_pack_run.json` and `initial_vehicle_fixture.log` retain failed screenshot
directory creation using `res://` as an absolute filesystem path. The fixture now
globalizes its report path, and the package rerun passes with a saved capture.
Neither failed run is counted as a passing check.

## Reproduce

From the project directory, use the configured Godot runtime:

```text
python tools/run_godot_check.py developer_tools --timeout 120 --require "failures=0" -- --gameplay-construction --no-zombies --vehicle-fleet --ground-cover
python tools/run_godot_check.py developer_vehicle_spawn --timeout 90 --require "failures=0" -- --gameplay-construction --no-zombies --vehicle-fleet --ground-cover
python tools/run_godot_check.py developer_belt --timeout 90 --require "failures=0" -- --gameplay-construction --no-zombies --vehicle-fleet --ground-cover
python tools/run_godot_check.py gameplay_items --timeout 100 --require "GAMEPLAY_ITEMS failures=0" -- --gameplay-construction --no-zombies --vehicle-fleet --ground-cover
python tools/run_godot_check.py zombie_population --headless --timeout 45 --require "failures=0"
python tools/run_godot_check.py zombie_population --headless --timeout 45 --require "failures=0" -- --population-read=res://reports/zombie_population/population_extended.bin
```

The UI test deliberately disables procedural admission before explicit spawning;
the separate population-world regression exercises ordinary procedural residency.
Additional entity families are not fabricated. Existing settlement NPC authoring
remains in the Actors Alt workspace. Earlier traversal, resident-construction
hitches and broader world-quality qualification remain separate work.
