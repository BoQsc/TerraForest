# Development map teleport verification

2026-10-25. Development mode only: open M, hold Ctrl and left-click a world
position. Release completes the gesture. Ctrl-drag pans, dropping Ctrl cancels,
ordinary clicks track destinations, and gameplay players cannot teleport.
Destination travel reuses the existing height query and collision/floor loading
barrier. No terrain, inventory, navigation or save-format changes.

## Passing checks

- `source-run.json` / `source-console.log`: 21/21 interaction checks, rendered
  source runtime, temporary seed 1703 / generator 21, 37.8 seconds for the whole
  test (not the teleport alone).
- `pack-run.json` / `pack-console.log`: 21/21 checks against the exported PCK,
  temporary isolated world slot, 36.8 seconds for the whole test. The manifest
  records the pack hash and external fixture hash; the fixture loads the actual
  packed game resources.
- `export.log`: export and headless packaged startup pass with 14 external native
  libraries. No native rebuild was needed.
- `map_hint.png`, `loading.png`, `arrival.png`: inspected final packaged frames.
  The development hint fits the sidebar; the ordinary loading screen precedes
  arrival in forest terrain. These are interaction evidence, not world-quality
  acceptance or a performance benchmark.

Checks cover gameplay/direct-call gating, marker tracking, plain clicks,
Ctrl-drag, cancelled modifier, invalid coordinates, driving/preparation guards,
release timing, pan/zoom coordinate conversion, menu close, movement reset,
duplicate rejection, collision-ready arrival, mouse capture and unchanged
inventory/terrain revision. The marker named "Map click fixture" is explicitly
added by the temporary test, not a generated settlement.

Reproduce source interaction checks:

```powershell
python tools/run_godot_check.py world_map_teleport --timeout 160 --require 'WORLD_MAP_TELEPORT checks=21 failures=0' -- --gameplay-construction --no-zombies --ground-cover --vehicle-fleet --world-generator=21 --world-seed=1703
```

## Failed checks retained

- `initial-fixture-run.json` / `initial-fixture-console.log`: the first fixture
  assumed the temporary world already contained a public map destination and
  indexed an empty array. Its owned test process was stopped. The final fixture
  adds its own presentation-only marker and explicitly selects generator 21.
- `legacy-map-run.json` / `legacy-map-console.log` / `legacy-map-result.json`:
  the older broad map test reports two failing road assertions and an index error.
  It assumes four base road segments and indexes authored roads at offset four;
  the map reports 96 segments with generator 16. Its other interaction assertions
  pass. This change does not modify road generation or rendering, and does not
  claim that the whole map suite passes. That separate fixture still needs to be
  reconciled with the current segmented-road contract, then rerun.

Arbitrary ocean, occupied interior and extensively edited-terrain destinations
retain the existing teleport landing policy; this check does not qualify every
possible landing location. User saves were not edited; tests use temporary slots.
