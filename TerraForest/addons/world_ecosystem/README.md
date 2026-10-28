# World Ecosystem addon

Optional integration between `TerrainWorld`, `VegetationWorld`, and a perspective `Camera3D`. Assign all three before adding the coordinator to the tree. Initialize terrain and vegetation first. The demo shows this wiring in `demo/world.gd`.

The coordinator maintains 64 m placement cells, with a deterministic jittered 6Ã—6 candidate grid per cell. IDs depend on cell and grid position, and random variation depends on seed, so request/visit order cannot alter placement. A grassy-biome mask, slope filter and native density support reject unsuitable positions.

Defaults: 640 m conservative circular preload coverage, at most 441 resident cells (405 selected away from world edges), two in-flight batches, at most one new batch per frame, 36 candidates per batch. Native selection covers the entire camera-owner square, retaining at least 64 m beyond the 576 m visual cutoff even at owner corners. Nearest cells are admitted first with a stable tie-break. `VegetationWorld.root_limit` independently bounds accepted roots. Distance fading finishes before ordinary residency retirement. Publication remains asynchronous; teleport/loading continuity is not guaranteed by this geometric margin alone. A full reconciliation can take up to 441 frames; the older 169-owner measurements below are historical.

Queries are worker jobs with immutable positions and stamped epoch/revision. Results are discarded after edits, reloads or travel out of residency. Terrain edits queue support revalidation for intersecting placement owners after publication. Existing trees remain visible until the replacement support result arrives. A native batch tests trilinearly interpolated density 0.35 m above and below each original surface candidate; edited-column metadata no longer excludes otherwise supported trees. Underground excavations therefore preserve surface trees. Travel/reload derives the same eligibility from saved terrain density, without a separate vegetation save file.

`reset()` invalidates pending coordinator tokens and removes owned vegetation. Native work already running finishes normally and its stale result is ignored. Resident candidates, query tokens and render owners are bounded; no travel history is accumulated. Core renderers remain usable without this addon.

Natural vegetation cannot become newly slope-eligible merely because mining
flattens a small facet. Native surface command 17 retains the edited root height
and uses the stricter inclination of its original generated support and current
support. This normal is vegetation eligibility data, not a replacement terrain
lighting or collision normal. Original support is reconstructed only where the
bounded root/normal footprint intersects authored density pages; untouched ground
keeps its existing query path. Both samples use the same quantized lattice and
local 0.35 m support bracket. Unsupported roots still disappear, shallow grading
still updates valid roots, and reload derives the same result from terrain alone.
No new saved state, candidate budget, shader or per-frame scan is introduced.

Optionally assign `structures` to a `NativeBlockWorld` or the `structures_world.gd` adapter before entering the tree. The main demo uses the adapter, whose native query unions block and registered model exclusion. Queries check transformed source-tree bounds plus the maximum supported wind margin. They retain vertical separation: underground rooms and sufficiently high structures do not clear unrelated trees. Empty portions of a partial block shape are conservatively reserved as the full cell; model compound parts are tested separately to preserve their gaps.

Accepted terrain samples are cached only while their placement owner is resident (at most 36 candidates per owner). Block changes coalesce into a queue, reconciled one owner per frame. Incoming terrain results check current occupancy immediately before publication. Demolition restores eligible cached candidates without a terrain query. Renderer publication removes missing IDs and replaces changed transforms while preserving unchanged rows and their LOD/fade state. At the default 169-owner cap a complete structure reconciliation can take 169 frames. The cache is released on eviction/reset. Restoring original terrain support can restore a procedural tree; persistent chopping/removal identities are not implemented by this policy.

This integration covers block construction and registered static models, including objects without resident collision. Native model queries use configured proxy parts, falling back to mesh bounds when no proxy is configured. Placement, removal, restore, proxy reconfiguration and collection transform changes queue reconciliation. Disabling collision does not disable exclusion. Model assets must be reconfigured after in-place mesh-bound changes. Moving the entire block-world node after startup still requires calling `_structures_changed()` on the coordinator. The coordinator and legacy forest renderer remain GDScript; block/model overlap tests and mask combination run in C++. Reconciliation is eventual, not an immediate frame-wide cutout: all cached owners may be queued after an edit, with one owner processed per frame.


## Interactive ground cover

Extended understory mesh LOD is default-on: fern 1512/392/154 triangles,
low/woody bush 638/294/154, dry twigs 372/136/80. Native renderer index selection
adds no per-instance scripts or runtime mesh generation. Near geometry, density,
harvest identity, shadows, grass tiers and ground-cover draw distance are unchanged.
`woodland_mesh.build(species, true, false)` retains the previous tiers for comparison.
See [current evidence and limits](../../issues/vegetation-lod/README.md).

`ground_cover.gd` coordinates native batches with persistent interactive identities for stones, plants and grass clumps. The main world now uses `woodland_mesh.gd`: an original temperate woodland sample with a textured stone, fern-like understory plant and mixed green/dry grass tuft. Shared startup geometry and shader wind replace the earlier simple assets; there are no per-instance scripts or animation nodes. See [art source and limits](art/README.md). The earlier `ground_mesh.gd` remains for comparison fixtures.

Removal/placement, inventory, save state, native picking envelopes and existing residency budgets remain. Near grass casts shadows within a 24 m page-distance band; other cover uses 48 m (page bounds/padding apply). Distant foliage uses approximate root self-shading, not projected ground shadows. Grass has 468/72/8/3-triangle mesh tiers and fades from 100 to 124 m. The artwork is a first visual pass for human review, not final art, a finished biome distribution or performance qualification.

Evidence: `docs/evidence/woodland_art` records14 visual/geometry checks,28 native LOD checks and66 actual-world interaction/exclusion checks. One world screenshot shows51FPS; no sustained60FPS or GPU/thermal claim follows. The earlier prototype GPU-cost failure in `docs/evidence/ground_mesh` remains historical failing evidence and cannot qualify these more detailed assets.

Natural ground support pipelines at most four 64-point requests for one owner.
Terrain admission limits and edit priority remain unchanged; rejected admission
retries the same layer. Replies are assembled by layer, so arrival order cannot
change persistent IDs or renderer ordering. An invalid reply abandons that wave,
drains remaining replies and retries; no partial owner is published. The resident
limit is 81 owners, with all 16 candidate layers retained throughout residency.

Camera FOV now selects bounded directional ground coverage: ordinary75 degrees
keeps124 m; zoom can extend to248 m while retaining nearby cells and no more
than81 owners. Native render-radius updates preserve existing pages. This is
ready for camera zoom consumers; no new gameplay zoom binding is added. New
cells still load asynchronously. See docs/evidence/vegetation_zoom for limits.


### Gatherable woody bush

Species 8 (item 212) is a taller variant of the existing low bush, approximately
twice the grass mesh height. It occurs sparsely among natural cover and is also
available in the development vegetation palette. Its shared near/far meshes use
638/294 triangles, existing wind/fading, and normal nearby cast shadows. No
per-instance script or physics body is added. Existing grass candidate identities,
density and the 81-owner streaming cap remain; roughly 0.5% of eligible grass
candidates now become woody bushes.

Gameplay attacks with any of the four tools or empty hands require two hits and
yield one wood on destruction. Tool wear follows the shared attack path. Collect
cannot bypass bush health. Item 212 can be placed, has an offline inventory icon
and a matching batched dropped model. State format 3 adds species 8 and still
reads formats 1 and 2. Existing authored species and removal identities persist.

See `docs/evidence/woody_bush` for the integrated interaction and visual check.
This feature check is not a sustained performance or final art acceptance claim.
