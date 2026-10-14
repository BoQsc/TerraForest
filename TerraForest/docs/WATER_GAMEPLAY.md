# Water in the playable world

Updated 2026-10-14. Water is static, editable volumetric water. Automatic flow,
settling and spillage are deliberately out of scope. This guide describes the
installed implementation; [older implementation notes](WATER_IMPLEMENTATION_HISTORY.md)
are historical, not current behavior or acceptance claims.

## Playing

- **Review Water Buckets.cmd** opens a disposable world with a lake and bucket.
  Changes are discarded; it does not load or overwrite player saves.
- **Play Water Gameplay.cmd** opens the separate persistent `water_gameplay_v2`
  world. Save through the normal menu or F5. Existing world data takes precedence
  over starter generation.
- Select the water bucket. Left click collects one full water unit; right click
  places one full unit. One gameplay unit is **1 cubic metre**. Transfers are
  atomic: a rejected action keeps both inventory and world quantities unchanged.
- A return near a connected gap first fills that local gap below the existing
  water level. It does not require aiming at exactly the same point as the scoop.
  This runs on the explicit pour only; existing water does not move by itself.
- Placement on dry ground uses a compact local volume. It stays where placed.
  Mining underneath water can expose its underside; it will not fall into the
  excavation. Previously placed pillars are not automatically repaired.
- Development mode provides Water controls for adding a full unit and removing
  water locally. The removal brush edits water, not terrain, and reports actual
  removed quantity or the reason the edit was rejected.

The one-cubic-metre bucket is a gameplay choice, not a physically sized household
bucket. Internal storage uses integer millilitres for exact accounting. Legacy
partial buckets retain their contents and can be refilled; fractional pouring
is not the current interaction contract.

## Architecture and cost

`NativeRegionalWater` is the sole water owner. It stores half-metre cells in
four-metre regions. Terrain and water share density-surface extraction, but
**do not yet share authoritative storage**. Full TerrainCore storage migration
remains unfinished; shared meshing must not be described as completing it.

Idle water performs no flow simulation. Explicit edits update local state and
invalidate affected meshes. The return planner reads only prepared cells within
a bounded two-metre neighbourhood; it does not search the entire lake or load
remote terrain. Separate dry-ground placement retains its own local admission
checks. There are no per-cell scene nodes or physics bodies.

Terrain occupancy comes from the terrain worker. Water edits wait for required
occupancy and validate inventory revisions before committing. Terrain deposition
deletes the water its solid volume replaces; excavation does not restore it.
Building cubes, slabs, stairs, slopes, posts and spheres participate in water
occupancy: placing one deletes the water its solid shape replaces. Their empty
portions retain water. Vehicle shapes are not yet included. Building bucket
interactions and full compound disk-save validation remain open.

Mesh preparation/publication has bounded work queues and cooperative budgets.
Bucket picking uses the published water surface. Cached meshes must be published
before normal saved-world play begins. These mechanisms do not establish a hard
frame-time bound or sustained laptop performance.

## Saving and loading

The compound world save preserves terrain edits, water quantities and bucket
inventory together. The versioned water snapshot includes cached terrain-contact
data; valid caches reopen without resampling terrain. Invalid or unfinished
regions still require preparation. Meshes are rebuilt from cached data; GPU
objects are not serialized.

The decoder validates bounds, ordered region keys and quantity totals before
replacing live state. Archive checksums and checkpoint recovery apply. The
preparation launcher bakes the saved spawn area, not an unlimited entire world.
Legacy save compatibility does not certify every historical shoreline or excess
quantity as visually correct.

## Current evidence and limits

- Changed-aim returns: 18 native cases across region interiors, faces and corners,
  debug and release; actual shoreline mouse-input returns restore original cells.
  See [nearby-return evidence](evidence/water_nearby_return/status.txt).
- Adjacent/stacked pool placement, cached reload and complete recovery:
  [pool recovery](evidence/water_pool_recovery/status.txt), with a further run in
  `evidence/water_nearby_return/pool_pass.log` after the return correction.
- Ordinary compound disk save/reopen: `evidence/water_pool_recovery/compound_disk_pass.log`.
- Shared boundary topology: [boundary correction](evidence/water_boundary_fix/status.txt).
- Underwater contact bands and underside ripples have targeted visual evidence in
  `evidence/water_underwater_fog/` and `evidence/water_underside/`.

These are specific checks, not blanket visual acceptance. Arbitrary terrain
contact, unwanted fragments, repeated edits and human review remain acceptance
concerns. The resident store is capped at 4,096 regions; wet-region disk paging
and large-ocean support are unfinished. Structure occupancy, combined endurance,
thermal sustainability and large multiplayer qualification are also unfinished.
No automatic flow or long-range liquid transport is required in this phase.

## Short checks

Run one graphical game at a time. From the project directory:

```text
python tools/run_godot_check.py water_return_nearby --headless --timeout 10 --require "WATER_RETURN_NEARBY failures=0"
python tools/run_godot_check.py water_return_shore --timeout 60 --require "WATER_RETURN_SHORE failures=0" -- --gameplay-construction --water-gameplay --water-bucket-review
python tools/run_godot_check.py water_pool_gameplay --timeout 60 --require "WATER_POOL_GAMEPLAY failures=0" -- --gameplay-construction --water-gameplay --water-bucket-review
```

The graphical checks use the actual world at 1920x1080. The older flow/outlet
checks in the historical guide are not acceptance tests for static water.
Project code and original bucket assets remain 0BSD, built with pinned Zig and
prebuilt godot-cpp.
