# Finite water in the playable world

Run **Play Water Gameplay.cmd**. It opens the normal TerraForest world, fullscreen at 1920×1080 with a 60 FPS cap, using the separate persistent `water_gameplay` slot. When the slot has no lake, this launcher authors one near spawn, compiles finite water on the terrain worker, equips the starter bucket if available, and saves. Subsequent visits reopen existing lakes without resetting their quantities. If you deliberately remove every lake, this dedicated launcher authors another; use the regular launcher to keep a lake-free world.

Walk to the waterline and aim at nearby water. Left click scoops one litre; right click pours one litre. A bucket holds ten litres, and its label shows its contents. G drops it. Backpack/toolbelt moves, chest transfers, drops/recollection and world saving preserve the water in the bucket. Inventory crafting provides an empty bucket for two metal. Existing game saves get the recipe, not an automatic inventory refill. Development > Water also offers an explicit give-bucket button.

The same lake and bucket implementation is used in Combined Gameplay and other normal world launches. To author water there, enter development mode with ~, open Esc > Water and use Carve lake at aim. Use Esc's Save world action or F5 to save terrain, lake quantities, inventory and dropped items together.

## Architecture and conservation

`NativeWaterRuntime` orchestrates the existing native field, topology, basin, regional storage and finite-network compilers on the terrain-owned worker. It first selects the seed-connected basin and reduces redundant parallel boundary openings, preserving the exact spill heights needed for storage. One worker slice is outstanding, using a soft 2ms native work budget. The main-thread scene manager shares one surface-work slice across lakes, with at most one regional mesh upload per frame. Uploads and some allocations are indivisible; this is not a hard frame-time guarantee.

Scoop/pour is a serialized native transaction. The solver stages an exact 1000ml change, checks the selected inventory slot/revision, then commits both owners. A full bucket, empty bucket, insufficient water/capacity, or stale inventory revision rolls water back. Bucket fill states use eleven nonstackable item IDs (401–411); all dropped bucket states share one batched mesh/store and retain the actual item state in native container storage. Idle water has no ongoing fluid solve.

The lake catalog's version 2 format saves native solver quantities plus a storage-geometry signature. Version 1 fixed-level lake definitions remain readable and acquire finite quantities on their first successful bake. Restoring version 2 recompiles against the saved terrain and validates quantities before publishing. An incompatible hierarchy reports failure and retains saved quantities rather than refilling the lake. The ordinary checksummed compound world archive provides disk publication; there is no separate bucket save file.

During small bucket changes, the previous surface stays visible until its replacement is ready. This is deliberate visual update latency: authoritative quantities change immediately. It only retains geometry from a still-current network; generation invalidation/retirement cannot keep an obsolete surface visible. Rapid clicks coalesce into the latest pending mesh.

## Explicit boundaries

- This is finite hydrostatic basin water, not a velocity/pressure simulation. No waterfalls, currents or arbitrary ground spills yet.
- Buckets transfer whole litres into existing compiled lake basins; they cannot create a new water region by pouring anywhere. Fractions below one litre remain in the lake.
- Terrain edits intersecting an established lake's sampled regions/halo are refused. Remove the water explicitly in Development > Water before reshaping. The tested native remapper is not yet a rollback-safe terrain/world transaction.
- Independent lake definitions cannot overlap owned regions. Legacy overlaps are retained but blocked with an explanation until resolved.
- Per-body limits remain 64 active regions, 4096 local basin leaves and 256 common storage anchors; authored ceiling is maximum capacity. Unsupported/open basins fail explicitly. There is no unbounded/unloaded-region flow.
- Initial/reload water compilation is asynchronous, not a cached precompiled network. Large populations, old-laptop thermal sustainability and long-session 60 FPS are **not qualified** by this functional check.

## Repeatable checks

`python tools/check_water_playable.py` runs the real world in a unique test-owned save slot. It exercises actual gameplay left-click routing, exact litres, full/empty/stale-action rollback, chest and dropped-bucket handling, normal world disk save, complete scene disposal and fresh world reopening, surface publication and a 1920×1080 screenshot. `--headless` runs the same correctness path without rendering. Successful runs remove only their own uniquely named save files.

`python tools/run_godot_check.py water_launch --timeout 55 --require "WATER_LAUNCH failures=0" -- --gameplay-construction --water-gameplay` checks the starter launch and both mouse actions in a disposable world.

Both native addons are 0BSD project code built with the pinned Zig/prebuilt godot-cpp toolchain. The bucket mesh/icon are original procedurally authored assets.
