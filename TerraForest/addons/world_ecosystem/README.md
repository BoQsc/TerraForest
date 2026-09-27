# World Ecosystem addon

Optional integration between `TerrainWorld`, `VegetationWorld`, and a perspective `Camera3D`. Assign all three before adding the coordinator to the tree. Initialize terrain and vegetation first. The demo shows this wiring in `demo/world.gd`.

The coordinator maintains 64 m placement cells, with a deterministic jittered 6×6 candidate grid per cell. IDs depend on cell and grid position, and random variation depends on seed, so request/visit order cannot alter placement. A grassy-biome mask, slope filter and native density support reject unsuitable positions.

Defaults: stream radius 384 m, at most 169 resident cells, two in-flight batches, at most one new batch per frame, 36 candidates per batch. Nearest cells are admitted first with a stable tie-break. `VegetationWorld.root_limit` independently bounds accepted roots. Keep draw distance inside the streamed coverage for expected travel speeds; the current residency boundary is cell-based and does not use a dedicated streaming fade.

Queries are worker jobs with immutable positions and stamped epoch/revision. Results are discarded after edits, reloads or travel out of residency. Terrain edits remove roots in affected columns after publication; other roots retain their owner, LOD and fade state without resampling or cell-wide disappearance. Edited 16 m columns remain excluded using terrain's persistent modification metadata. No separate vegetation save file can fall out of sync with terrain.

`reset()` invalidates pending coordinator tokens and removes owned vegetation. Native work already running finishes normally and its stale result is ignored. Resident candidates, query tokens and render owners are bounded; no travel history is accumulated. Core renderers remain usable without this addon.
