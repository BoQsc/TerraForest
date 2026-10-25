# Approved-building readiness audit — 2026-10-25

The current approved building requests are A2's thin cottage roof, B1 as an
additional hipped shop, and B2's thin shop roof. Their production integration is
in commit `00794189`; no further roof geometry or house redesign is introduced
by this audit. Existing player worlds are not regenerated or migrated.

## Loading failure found and fixed

The default-generation audit exposed a real destination-loading failure after
teleporting from the market to the northern settlement. The user also observed
the failed-loading screen. The native terrain planner rejected navigation-interest
points left over from the previous encounter: after the focus moved, they were
outside its 128 m interest budget. Generation/publication itself had completed.

`demo/world.gd` now clears encounter residency through its existing shared
residency coordinator **before** the base teleport changes player/terrain focus.
This clears the coordinator's cached points and the terrain, block, model and
tree-collision consumers together. New destination interests can resume normally.
Native budget validation remains intact; errors are not hidden or ignored.

The deterministic regression seeds a valid old-location interest immediately
before the actual Ctrl-click travel action. It reproduces the same native error
without the fix and passes 25 checks with it, including destination collision,
resumed navigation interests and unchanged terrain/inventory. The interrupted
integrated failure and focused before-fix failure are retained separately.

## Generator verification

`world_recipe_generation --default-recipe` leaves the generator controls untouched:
woodland, two settlements, one district each, ordinary network and one trail
level, seed 1703. It generates 20 buildings and 395 public road segments, enters
play, streams an A2, B1 and B2, saves, returns to the selector and reopens the
saved world using the selector's normal open action. All 31 checks pass.

The test independently rebuilds the deterministic placement plan, compares the
entire native district/road snapshot, and compares every transformed block in
the three approved buildings before and after reload. Each remote building must
first become resident with complete collision. Normal vegetation, actor, vehicle
and gameplay systems are enabled; reload no longer injects a no-zombies override.
All transitions retain the same native window handle. Only isolated
`recipe_generated_*` saves are used.

The six-district custom recipe is also rerun with the same stronger assertions:
three settlements, two districts each, woodland/meadow mosaic, loop network and
two trail levels. Its 68-building generation and roundtrip pass all 30 checks.
The complete test processes take 59.74 s (default) and 109.38 s (custom), including
generation, loading, travel, screenshots, save and reopen; these are not bare
generation timings or frame-performance benchmarks.

`Worlds.cmd` launches the current source project's `demo/worlds.tscn`, not the
exported pack. This audit exercises that same browser and session path. The
exported pack is checked separately, not substituted for the user's launcher.
The pack is rebuilt with the fix; startup with all 14 native libraries passes.
The external standalone teleport regression also passes all 25 checks against
production resources loaded from the PCK, not the source project.

## Stale settlement fixtures closed

- The tower gained four sloping stair-rail objects in `9ee47904`; the old
  attachment expectation remained 66 instead of 70. A 64-tower layout therefore
  has 4,480 objects, not 4,224. Capacity tests now use independent source-count
  arithmetic and verify the last safe paired lot and the first rejected one.
- The seeded mixed preset still chooses exactly five cottages and three towers.
  Its current total is 7,212 blocks and 275 attachments. Assertions now use this
  fixed composition with current source counts, verify the exact UI settings,
  and retain invalid/oversized request rejection. They do not compare the
  production counter against itself or relax the native 4,096-object limit.
- Both settlement suites pass. Their historical failures remain in
  `../approved_cottage_roof/`; they are superseded, not erased.

## Initial audit fixture correction

The first audit fixture incorrectly reused a six-district minimum road count for
the two-district default, and read remote block cells before region paging had
loaded them. `initial_fixture/` retains those failures and that exact fixture.
The revised check compares complete planned navigation bytes instead of an
arbitrary count threshold, and explicitly loads each destination before inspecting
its blocks. This then exposed the separate, genuine navigation-interest failure
described above. `failed_destination_loading/` and `teleport_before_fix/` are not
counted as passes.

The first external packed-test invocation named a sibling engine executable not
present in this installation. It failed to launch, before starting the game;
`pack_launch_path_failure/run.json` retains that result. The repeated invocation
uses the same discovered engine as the normal test launcher.

## Scope

This is readiness for a new-world playtest of the approved buildings, not blanket
acceptance of every settlement, arbitrary seed, long-distance frame performance,
NPC navigation scenario or the entire historical project backlog. Existing
world-quality rejection and unfinished milestones remain in
`../../WORLD_FOUNDATION_STATUS.md`. The playable screenshot is a loading/reload
check, not a replacement for the user-approved roof comparison images.

## Reproduce

```text
python tools/run_godot_check.py settlement_capacity --headless --timeout 90 --require "SETTLEMENT_CAPACITY failures=0"
python tools/run_godot_check.py settlement_presets --timeout 90 --require "SETTLEMENT_PRESETS failures=0"
python tools/run_godot_check.py world_map_teleport --timeout 160 --require "WORLD_MAP_TELEPORT checks=" -- --ground-cover --actors --no-zombies
python tools/run_godot_check.py world_recipe_generation --timeout 600 --require "WORLD_RECIPE_GENERATION checks=" -- --default-recipe
python tools/run_godot_check.py world_recipe_generation --timeout 600 --require "WORLD_RECIPE_GENERATION checks="
```
