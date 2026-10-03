# Native block structures and static models

Fresh block worlds can now initialize checkpoint availability metadata without
loading cell chunks; see [region bootstrap](../../docs/BLOCK_REGION_BOOTSTRAP.md). Automatic paging and saving
partially loaded worlds remain unfinished.

The main world now publishes block-region checkpoint references through a native
archive adapter, retaining current and backup roots. See [region-backed world saves](../../docs/REGION_WORLD_ARCHIVE.md).
Full-resident capture/restore limits remain; automatic runtime paging is unfinished.

Persistent native catalog checkpoints now preserve referenced block versions through
future edits and collection. See [checkpoint API](../../docs/BLOCK_REGION_CHECKPOINTS.md). World-root integration remains pending.

`raycast_cells(from, to)` selects authored shapes without waiting for mesh or
collision baking. `raycast_scene(from, to, collision_mask=3, exclude=[])` also
respects nearer scene collision while ignoring stale bodies belonging to this
block world. See [API limits and validation](../../docs/BLOCK_PICKING_VALIDATION.md).

Independent Godot 4.7 Windows x86-64 addon. Copy this directory into a project; the GDExtension registers `NativeBlockWorld` and `NativeStaticBatch`. No terrain, vegetation or other TerraForest addon is required. Native sources and both debug/release DLLs are included. Build using the repository's pinned Zig/prebuilt godot-cpp toolchain:

```text
python tools/build_native.py --addon structures --target all
```

## Representation and editing

`NativeBlockWorld` is a Node3D with sparse 16×16×16 cell chunks. Each cell is a 16-bit word; a resident chunk's cell payload is 8 KiB. A cell is one local metre. Translation/rotation can be applied to the world node; supply focus in that node's local coordinates. Nonuniform scaling is not a supported physics configuration. There is no node per block.

`set_cells(PackedInt32Array)` accepts `[x,y,z,word, ...]`, up to 262,144 records. Coordinates are signed integers in ±1,048,575. Word zero erases. Nonzero words encode `shape | (rotation << 3) | (material << 5)`:

| Field | Values |
| --- | --- |
| Shape | 1 cube, 2 lower half slab, 3 four-step staircase, 4 planar slope, 5 centred half-width post, 6 sphere |
| Rotation | 0–3 quarter turns about Y |
| Material | 0 brick, 1 wood, 2 concrete, 3 metal |

The entire batch is validated and staged before modification; repeated coordinates use their final value. Invalid input or exceeding the 2,048 resident chunk capacity leaves the world unchanged. Empty chunks are reclaimed. Authoring methods and snapshot capture/restore run on the main thread. `validate_snapshot` reads only its argument and can run on a worker. General concurrent authoring is not supported.

## Baking and rendering

Changes invalidate the edited chunk and resident face neighbours. One native worker receives an immutable 18³ cell halo, generates geometry without accessing Godot objects, and returns plain buffers. Main-thread publication checks a dependency ticket and rejects obsolete work. Worker completions and cached meshes share bounded publication batches. A repeated edit deduplicates pending work; abandoned empty chunks do not leave historical queue entries.

The worker starts lazily and sleeps between jobs, reusing one thread per block-world instance. One outstanding submission/result slot bounds its work. Destruction wakes and joins the worker; an executing bake finishes before destruction returns. `stats()` exposes `worker_threads_started`, `worker_jobs_submitted` and `worker_results_consumed`. Cached returns need no submission. See [worker lifecycle validation](../../docs/BLOCK_WORKER_VALIDATION.md).

The native worker chooses an exact temporary bake lattice from the chunk and its halo: whole cells for cubes, half cells when slabs are present, and quarter cells for stairs or posts. Greedy face merging removes hidden boundaries and combines coplanar regions of the same material, including across block edges. Chunk boundaries hide internal faces but do not merge separate chunk meshes. Slopes use an exact planar wedge; wedge boundaries currently use conservative geometry and are not greedily merged or clipped against neighbours. This adaptive scratch grid preserves geometry and texture coordinates; it is not distance-based LOD. `stats()` reports resident visual counts as `bake_lattice_16_chunks`, `bake_lattice_32_chunks` and `bake_lattice_64_chunks`. See [exact bake validation](../../docs/BLOCK_LATTICE_VALIDATION.md).

Each occupied visual chunk is one ArrayMesh surface with a shared texture array.
The four material IDs remain Brick (0), Wood (1), Concrete (2) and Metal (3).
Two interchangeable image sets live in `textures/original/` and
`textures/terraforest/`, each containing `brick_albedo.png`, `wood_albedo.png`,
`concrete_albedo.png` and `metal_albedo.png`. The original 128² RGB images were
exported from the legacy generator; their regenerated mip chains match every
byte in `tests/fixtures/block_material_tiles.json`. Keep this folder as the first
alternative. The unchanged deterministic generator is also retained as the
fallback when the original images are unavailable.

The TerraForest alternative contains generated 1024² RGB albedo images inspired
by the supplied reference: dark aged brick, rough wood planks, weathered concrete
and worn painted metal. These are a first visual trial; distinctive knots, stains
and brick variation can reveal repetition on large walls. Normal, roughness and
metalness maps are not included. The existing roughness and metal settings remain
in the shader. Flat faces repeat approximately once per world meter; changing
resolution changes detail, not the world scale of the pattern.

`project.godot` defaults to `[structures] material_set="terraforest"`. Set it to
`"original"` to restore the preserved originals as the default, or override one launch:

```sh
python tools/run.py --scene structures --block-textures terraforest
python tools/run.py --block-textures terraforest
python tools/run.py --block-textures original
```

In the structures showcase, **F6** switches the sets live. The native API is
`set_texture_set("original" | "terraforest") -> bool` and `get_texture_set()`.
Switching updates the shared material on existing chunks without changing
geometry, physics, material IDs, undo history, prefabs or saves. Unknown names
and failed loads return false and retain the current material. At startup, an
invalid project/launch selection warns and falls back to originals.

PNG source files are read directly in the checkout; exported packs load their
lossless imported textures instead. Both paths convert to RGB8 and generate
independent mip chains. Keep the supplied lossless import settings. Within a set all four
images must be square, the same size, and a power of two from 128 to 2048. Replace
images in `terraforest/`, then restart or switch away and back to reload. Do not
overwrite `original/`. Texture payload is separate from the mesh streaming budget;
the new RGB array is about 16 MiB including mipmaps, versus 256 KiB for originals.
The generator remains available even when PNG loading fails.

Validate with a graphical Godot run of `tests/block_texture_sets.gd`. The one-time
`tools/export_original_block_textures.gd` refuses to overwrite preserved originals.
`tools/prepare_block_textures.gd` only normalizes generated images to 1024² RGB;
it never edits the original folder. Image generation prompts and provenance are
recorded in `textures/terraforest/generation.json`.

Sphere cells have radius 0.5 m and are centred in their grid cell. Their native
indexed template has 91 vertices and 120 triangles, radial shading normals and
seam-aware UVs with three longitudinal texture repeats. Quarter turns rotate the
texture orientation; sphere geometry is rotationally symmetric at those angles.
The template is initialized once, then appended to chunk bake buffers; no sphere
nodes or per-sphere physics objects are created. A sphere surrounded on all six
faces by full cubes is omitted until a neighbour changes. Touching spheres keep
their curved surfaces. Collision uses the same faceted mesh, not an analytic
sphere primitive. Vegetation/player authoring exclusion still reserves the full
cell, as for other partial block shapes.

Curves cost more geometry than greedy cubes: a completely filled sphere chunk
can contain 491,520 triangles. Existing mesh admission limits apply; use repeated
static-model batching for large decorative instance populations. Sphere-specific
LOD and curved-shape greedy merging are not implemented. Shape 6 uses a previously
reserved cell code: new builds load existing saves, but older builds reject saves
containing spheres rather than silently changing their meaning. Prefab capture,
placement, undo/redo and compound snapshots support spheres. Press **6** in block
mode in either demo. See [sphere validation](../../docs/SPHERE_BLOCK_VALIDATION.md).

Nearby chunk collision uses the same triangles as rendering, on layer **2**. `set_focus(Vector3)` and `set_collision_radius(metres)` control residency; radius defaults to 48 and accepts 0–256. The native scheduler selects the nearest incomplete chunk and creates at most one 1,024-triangle piece per tick. Each chunk stays on layer zero until all pieces are installed, then activates as a whole. Leaving range or replacing geometry disables the old body and retires at most four pieces/empty bodies per tick. Pending retirements drain before admitting replacements. Collision range uses chunk centres plus a conservative 14 m extent. Engine calls and final activation remain non-preemptible; these are work-count limits, not hard time limits.

Block `collision_stats()` exposes `ready`, `pending_chunks`, `unresolved_mesh_chunks`, live/retired piece counts, retained source payload, work counters and timing maxima. `ready` covers currently authored chunks within the configured collision radius; disabled collision returns false, as do unresolved or mesh-budget-deferred near chunks. This is not a swept vehicle-path guarantee. The main-world walking controller uses `is_collision_region_ready(world_bounds)` to wait before entering unavailable authored block surfaces; empty space in an unfinished chunk remains traversable. Editor flight bypasses this gate. See [movement readiness](../../docs/BUILDING_MOVEMENT_READINESS.md) and [piece admission validation](../../docs/BUILDING_COLLISION_STREAMING.md).

`flush_bakes()` deliberately blocks for offline baking/tests, including all pending collision admission and retirement. Do not call it from a live gameplay frame loop. `stats()` reports cell payload, resident chunks, triangles, pending work and rejected stale bakes; `collision_chunks` counts completed bodies only.

### Mesh residency and bake reuse

`configure_streaming(enabled, radius, chunk_limit, mesh_byte_limit, cache_byte_limit)` opts into nearby mesh residency. The terrain demo uses a 384 m radius, 256 visual chunks, 64 MiB of mesh payload and 32 MiB of retained native bake buffers. The standalone addon defaults to nonstreamed authoring. Valid limits are radius 16–4,096 m, 1–2,048 visual chunks, 64 KiB–512 MiB of mesh payload and 0–512 MiB of bake cache. Invalid configurations preserve the previous settings; zero cache bytes disables reuse.

The native scheduler selects the nearest authored chunks within the radius plus a conservative 14 m chunk extent. It refreshes after edits/configuration changes or at least 8 m of focus movement, instead of scanning the world every idle frame. Leaving the selected set releases meshes and their physics bodies while preserving authored cells. A least-recently-used memory cache retains dependency-validated bake buffers; returning publishes cached geometry without another worker job. Edits invalidate the changed chunk and its face neighbours. Snapshot restoration clears cached geometry. A worker finishing outside the selected set may populate the cache without uploading a distant mesh.

`configure_mesh_uploads(chunk_limit, byte_limit, time_limit_us)` controls publication batches, defaulting to eight meshes, 512 KiB and a 1,500 microsecond soft elapsed-time threshold. Supported ranges are 1–16 meshes, 64 KiB–8 MiB and 100–5,000 microseconds. Invalid settings preserve the previous policy. Time is checked between uploads; a single engine call cannot be interrupted. One oversized first mesh may upload alone to prevent starvation. A worker completion counts toward the same frame budget; the worker is never waited on in the frame loop. `flush_bakes()` bypasses frame budgeting for explicit offline use. See [dense rendering evidence](../../docs/DENSE_BUILDING_RENDERING.md).

Mesh admission prefers nearby chunks and evicts farther meshes when needed. A chunk too large for the resident mesh budget stays deferred instead of rebaking every frame. `streaming_stats()` exposes mesh payload bytes, retained cache capacity, cache hits, worker launches, evictions, wanted/deferred chunks and `budget_blocked_chunks`, plus upload limits, last/high counts and bytes, oversized ticks and native stage timings. The demo displays a detail-limit notice when admission is blocked. `is_idle()` means no pending residency/bake work; it does **not** guarantee that budget-blocked geometry or player collision is available.

The mesh budget counts uploaded vertex attributes and indices, not complete VRAM, driver, ArrayMesh, material or physics memory. Cache accounting includes vector capacity, but excludes container metadata and transient worker scratch. Eviction runs on a residency refresh without a wall-time budget. Authoritative cells still remain in RAM, capped at 2,048 chunks; persistence remains whole-world snapshots. This is render/near-physics streaming with an in-memory bake cache. Disk region storage, distant building LOD and high-speed collision readiness remain pending. See [streaming validation](../../docs/BUILDING_STREAMING_VALIDATION.md).

## Static models

`NativeStaticBatch.set_instances(mesh, transforms)` accepts any Godot Mesh, including one extracted from an imported model. Transforms use Godot's 12-float MultiMesh row layout:

```text
xx xy xz origin_x   yx yy yz origin_y   zx zy zz origin_z
```

The native implementation validates finite, nonsingular transforms, partitions origins into signed 32 m spatial groups, shares the source mesh, and bulk uploads MultiMesh draw pages (one per group in eager mode). The limit is 100,000 instances and 4,096 groups per collection. An empty input clears the collection. This replacement API assigns IDs 1 through N in input order; use the incremental API below when identity must survive edits. Large models crossing group bounds retain their full rendering bounds but should use a suitable grouping/LOD strategy.

### Stable placements

Configure a collection with `configure_asset("architecture/fence/v1", mesh)`. The printable ASCII key (1–128 bytes, no spaces) identifies the application-resolved mesh; snapshots never load resource paths supplied by a file. A populated collection cannot switch to a different key. The same key may be rebound to a replacement Mesh, for example after an application-approved asset reload.

`upsert_instances(ids, transforms)` accepts positive signed 64-bit IDs and the same 12-float transforms. Existing IDs move; new IDs insert. Duplicate IDs, invalid transforms and capacity violations reject the whole transaction. With eager rendering, small edits within a spatial group update individual MultiMesh slots, with no full-buffer upload; more than 64 changed placements use a bulk upload. With render streaming enabled, same-group transform edits queue only affected render pages and retain other pages. Insertions, removals and cross-group moves rebuild the affected groups' pages because their sorted membership changes; unrelated groups retain nodes and buffers. Identical edits cause no upload. Capacity is validated against the final state, so moving a singleton group at the group limit is allowed.

`remove_instances(ids)` requires unique existing IDs and rejects the entire operation if any are missing. `get_ids()` returns sorted IDs, and `get_instance(id)` returns the 12-float authored transform, or an empty array when missing. IDs are scoped to this asset collection and assigned by the caller; global authority and ID allocation are application responsibilities. Mutation, capture and restore APIs are main-thread operations.

`capture_snapshot()` emits a versioned little-endian format containing the asset key, sorted IDs, float32 transforms and SHA-256 checksum. Configure a matching asset before restoration. `validate_snapshot()` validates only its byte argument and may run on a worker; `restore_snapshot()` also checks the configured asset identity before changing the collection. Input size, count, ordering, transform validity and spatial group limits are checked. Unconfigured collections return an empty byte array instead of saving an anonymous mesh. Snapshots preserve placement data, not Mesh resources. The application must resolve asset keys consistently on load.

Placement records, group membership and resident GPU slot indices remain in native memory. The `transform_bytes` statistic reports only the 48-byte authored transform payload per object, not total CPU/GPU memory or map overhead. Bulk initialization consequently does more work than the earlier renderer-only API; current regression evidence records this separately. Network replication, authoritative data region eviction and durable journal storage remain pending.

### Bounded model rendering

`configure_render_streaming(enabled, radius, batch_limit, byte_limit, uploads_per_tick, bytes_per_tick)` enables native nearby batch residency. Each origin group is split into render pages of at most 1,024 instances, reduced to fit smaller payload budgets. Batch counts and upload limits count pages; authored spatial groups stay unchanged. `set_render_focus(local_position)` supplies collection-local focus; `render_stats()` reports residency, pending uploads, capacity deferrals, page capacity, ordered-index capacity and cumulative upload payload. Selection uses maintained group mesh bounds, including models extending beyond their origin group. Four local units of padding allow focus changes below four units to avoid rescanning. See [limits](../../docs/STATIC_RENDER_STREAMING.md) and [dense-page validation](../../docs/DENSE_MODEL_PAGES.md).

Standalone native collections default to eager rendering. The world adapter enables a 384-unit radius, 128 batches, 4 MiB transform payload, two batch uploads and 256 KiB upload payload per process tick per collection. The main demo updates its collections from the player position. Adapter consumers must update each collection's local focus themselves. These are per-collection limits; aggregate limits across many asset types are still pending. Rendering eviction does not discard authored data, collision, undo history or vegetation exclusion. Reconfigure the asset after modifying mesh bounds in place.

### Model placement editor

In the main world, **M** enters object mode or returns to block mode. **1–3** selects a metal beam, floor panel or doorway; **R** rotates by 90 degrees, **RMB** places, and **LMB** removes the picked object. **Esc** releases the cursor to use the catalog buttons. **B** returns to terrain editing from object mode. F5/F9 use the existing compound world save path.

`model_tool.gd` is editor presentation/input glue with a single ghost mesh and a 10 Hz preview update. The native collection validates transforms, capacity and player clearance, allocates an ID, updates the spatial renderer/collision and signals save invalidation. Preview/placement uses upward-facing surfaces within 48 m, snaps X/Z to half metres, keeps the picked support height and offsets the mesh's lowest point to that height. It does not grade terrain, guarantee support under the full footprint, prevent intersection with existing objects. The main world reconciles vegetation asynchronously after placement. Green means the native insertion/player-clearance check passes; it does not guarantee collision is already resident.

`can_insert_instance(transform, protected_bounds=AABB())` is a read-only native preflight for one 12-float placement. `insert_instance(...)` revalidates and returns a positive ID, or zero without modification. IDs are one above the largest live ID; an empty collection starts at one, and INT64_MAX rejects automatic allocation. They are unique among current placements, not permanent network identities: deleting the highest ID or loading an older snapshot can allow reuse. Player protection uses conservative world-space AABBs of configured compound parts, or mesh bounds when no proxy is configured. Positive-volume protection is optional; malformed bounds reject the command. Arbitrary client authority/ID allocation is not a multiplayer protocol.

The catalog currently has three configured entries. Ctrl+Z/Y in object mode uses the native model journal described below. **E** selects an aimed existing model by its nearby native physics body. Selected objects have an amber overlay and transform buttons. Arrow keys move by 0.5 m along world X/Z; Page Up/Down moves on Y; Shift reduces movement to 0.1 m. **R** rotates 90 degrees around world up at the object's origin. **+ / −** scales all basis axes by 1.1 or its reciprocal about that origin. **Q**, changing the catalog entry or leaving object mode clears selection. RMB placement is suppressed while a model is selected. Release the mouse with Escape to use panel buttons, which apply the default movement/rotation/scale increments.

Each transform action is one native history command with player protection, capacity validation, incremental rendering, collision/exclusion updates and persistence invalidation. Own edits keep selection; undo, loads and external authored changes to that collection clear it so reused IDs cannot target stale selections. The overlay reads one transform at 10 Hz; GDScript provides UI/input glue and the native collection remains authoritative. Transform edits can overlap other objects or terrain and do not automatically ensure support. Only nearby collision-resident objects can be picked. Numeric entry, drag handles, multi-selection, per-axis scale, asset import UI and cross-addon transactions remain pending. See [transform validation](../../docs/MODEL_TRANSFORM_VALIDATION.md) and [model history validation](../../docs/MODEL_HISTORY_VALIDATION.md).

### Collision configuration

`configure_collision(box: AABB, radius, instance_limit, builds_per_tick)` opts into a box proxy for each placement in the collection. This is authored asset metadata: choose a box that represents the solid part of the model. It does not infer a collision mesh or make a hollow building traversable. Radius 0 disables collision and frees bodies. Accepted radius is 0–512 local metres, body limit 1–4,096, publication limit 1–64 per physics tick, positive box dimensions up to 4,096 and box-position components within ±4,096. Invalid configuration preserves current settings and bodies. The terrain demo configures its metal-beam collection with the source box bounds, radius 64, 512 bodies and eight creations per tick.

Supply focus in collection-local coordinates through `set_collision_focus`. The native scheduler refreshes after edits, configuration/transform changes or 4 m of focus movement. It checks maintained bounds for the existing 32 m groups, then individual transformed proxy bounds in overlapping groups. Selection includes a 4 m margin, uses distance to bounds instead of object origin, and retains the nearest placements up to the body cap. This allows a large model to intersect the nearby area even when its origin is in a distant group. Bounds are rebuilt for changed groups during authoring; a densely populated group can make that operation expensive. Selection may scan many placements in a dense nearby group, and is not wall-time-budgeted.

Collision uses layer **2**, one native physics-server static body and one eight-vertex convex shape per resident placement, with no per-placement scene nodes. The box's corners are transformed by the placement and collection bases before creating the convex shape. Nonuniform scale, rotation, reflection and shear therefore do not rely on scaled physics bodies. Collection transform changes rebuild nearby proxies; this is for static architecture, not a moving vehicle system. Invalid collection transforms suppress collision; nonfinite transformed vertices are skipped and reported. Very large coordinates and extremely thin geometry still require normal physics precision discipline.

Edits immediately retire affected bodies; replacement admission follows the per-tick budget. Removal, successful load, disabling collision, scene/physics-world exit and destruction release the corresponding handles. Rejected edits/loads preserve them. Reentry and physics-world reassignment rebuild in the current space. Unaffected bodies are retained. A ray result's `collider` is the collection node; `placement_for_body(hit.rid)` returns its positive 64-bit placement ID, or zero for a stale/foreign RID.

`collision_stats()` exposes resident/pending/candidate bodies, budget-deferred and invalid proxies, selection state, transform validity, builds and evictions. These limits are **per collection**; multiple collections need an application-wide budget. Selection and eviction do not have a time budget. Pending or deferred proxies provide no collision, so these counters are not a high-speed readiness guarantee. Proxy configuration is supplied again by the asset registry on load and is excluded from placement snapshots. Arbitrary concave mesh proxies, climbing ladders, predictive loading and advanced model editing remain pending. See [collision validation](../../docs/STATIC_COLLISION_VALIDATION.md).

### Compound architectural proxies

`configure_compound_collision(boxes: Array[AABB], radius, instance_limit, builds_per_tick, shape_limit, shapes_per_tick)` accepts 1–32 boxes in asset-local coordinates. Each box has the same validation rules as the single-box API. A placement retains one body and stable ID, with one convex shape per part. The union box is used only for conservative nearby selection; collision preserves gaps between parts, including doors, windows and spaces between stair treads. This is authored compound geometry, not automatic mesh decomposition.

Resident shape limits range from the asset's part count to 16,384; per-tick shape limits range from the part count to 256. Both must fit a complete object. Effective residency is the smaller of the body cap and `floor(shape_limit / parts)`. Effective creation throughput is the smaller of the body-per-tick cap and `floor(shapes_per_tick / parts)`. All vertices are checked before allocating any part, and the complete body is attached to the physics space together. Invalid configurations preserve existing bodies and settings. Metadata is copied, so later caller-array changes do not mutate retained geometry.

`collision_stats()` additionally reports `parts_per_body`, `resident_shapes`, `shape_limit` and `shapes_per_tick`. The existing single-box API uses the same path with one part, a 4,096-shape resident ceiling and 64-shape per-tick ceiling. Removal, editing, restore and lifecycle cleanup release all parts. Neither API persists shape metadata in placement snapshots: applications resolve the collision asset alongside the mesh.

`prefabs/doorway_model.tres` is a reusable one-surface model with two posts, a lintel and a two-metre-wide, two-metre-high opening. Its `collision_boxes` metadata is generated from the same three boxes as the visual mesh. Regenerate it offline with `godot --headless --path . --script res://tools/generate_architecture.gd`. The main demo registers it as `architecture/doorway/v1`, before sealing persistence; old saves without that asset restore it empty. Runtime scheduling and collision remain native. See [compound collision validation](../../docs/COMPOUND_COLLISION_VALIDATION.md).

### Model exclusion queries

`NativeStaticBatch.overlap_mask(transforms, prototype_bounds)` returns one byte per candidate (1 overlaps, 0 clear). Transforms are world-space, bounds are prototype-local, and input is limited to 65,536 finite nonsingular transforms with positive finite bounds. Invalid input returns an empty array. The query converts candidates into collection coordinates, filters maintained 32 m group bounds, then tests transformed AABBs of configured proxy parts. Without configured parts it uses mesh bounds. Compound openings remain available, but rotated/sheared AABBs can conservatively exclude more than the exact surface.

Queries use authored records, not resident physics. Disabling or evicting collision preserves exclusion. Group bounds are updated during authoring and rebuilt after restore. Reconfigure the asset after changing mesh bounds in place. `exclusion_changed` signals proxy/asset reconfiguration and collection transform changes; ordinary placement changes retain their `changed` signal. These are scene-thread APIs.

`NativeStructureQueries.overlap_mask(blocks, models, transforms, prototype_bounds)` combines one NativeBlockWorld and up to 256 NativeStaticBatch collections in C++, rejecting invalid collections or failed component queries. `structures_world.gd` exposes this through its own `overlap_mask` and combined `changed` signal. Assign that adapter to the optional ecosystem coordinator to exclude both blocks and models. Reconciliation uses the existing one-owner-per-frame queue, so trees may briefly intersect new objects before it drains. See [model exclusion validation](../../docs/MODEL_EXCLUSION_VALIDATION.md).

## Saves and present scope

### Reusable block prefabs

`NativeBlockPrefab.compose(sources, placements)` assembles existing modules in
C++. `sources` is an array of 1–256 nonempty native prefab resources; `placements`
contains up to 4,096 `[source_index, x, y, z, quarter_turns]` rows. Rotations are
0–3 and follow the same cell-centered convention as world prefab placement.
Coordinates, shape orientation and material are retained in the resulting asset.
The operation rejects overlapping cells, invalid references, out-of-range
coordinates and totals over 262,144 cells before replacing the destination.
Sources are unchanged, including when the destination is itself a source.

For example, place a floor module at successive floor-height offsets to author
a tower, then add stair and roof modules in the same placement list. The result
is a flattened reusable prefab, with the normal world placement, chunk meshing,
collision, history and resource serialization paths. Composition is synchronous
authoring work, not a per-frame operation. It does not preserve a live module
hierarchy, automatically connect stairs, grade terrain or generate a city layout.
See `tests/prefab_composition.gd` for rotation and sixteen-floor examples.

In the construction palette, select a prefab, enter a name, choose 2–32 repeats
and click **Stack selected prefab**. The library composes copies vertically at
the module's integer `stack_height` metadata when present, otherwise its
bounding-box height, saves a new personal asset and selects it for
normal preview/placement. It never changes the source module or existing world
blocks. This is a repeated-module authoring helper; use a suitable floor module
and verify stair openings and roof design yourself. The native cell/coordinate
limits still apply, and the personal library retains its 32-asset limit.

The supplied tower-floor module has a four-metre `stack_height`; its staircase
extends into the next level, so its five-metre bounds must not determine spacing.
Open stair undersides preserve headroom when repeated. Assemblies inherit the
combined pitch for further stacking. Explicit pitch must be an integer 1–4,095;
composition still rejects overlapping cells. `tests/tower_connectivity.gd`
checks quarter-step heights, landings and 1.85 m vertical clearance with native
geometry rays. It does not certify capsule traversal, navigation or building codes.

`NativeBlockPrefab` is a native Godot `Resource`. `configure(PackedInt32Array)` accepts occupied `[x,y,z,word]` records, validates them atomically, rejects duplicate coordinates, and sorts them for deterministic serialization. The shape/material words match `NativeBlockWorld`. Limits are 262,144 cells per asset and local coordinates from -4,095 to 4,095. `get_records()` returns independent data; empty assets are allowed for authoring but cannot be placed. Godot `ResourceSaver`/`ResourceLoader` support `.tres` files directly through the `records` property.

`can_place_prefab(asset, origin, quarter_turns, replace=false)` validates the complete destination against coordinate and world chunk limits. `place_prefab(...)` performs the same validation and commits all cells together through the native chunk edit path, emitting one logical change signal. The default rejects occupied destination cells. Explicit `replace=true` overwrites only listed cells; unlisted cells inside the bounding box remain untouched. Rotations 0–3 turn cell coordinates `(x,z)` to `(-z,x)` and rotate stair/slope orientation as well. The pivot is the centre of local cell `(0,0,0)`. `asset.placement_bounds(origin, turns)` returns the matching local-world cell bounds.

`capture_prefab(origin, size)` extracts existing block cells into a new resource, with origin-relative coordinates. Each dimension is 1–256 and the selection volume is limited to 262,144 cells. Invalid selections return null. The caller can name and save the resource. Capture and placement are native authoring operations, not per-frame world scans. Placed prefabs become ordinary editable cells and use existing chunk meshing, collision, vegetation exclusion and compound world persistence; they do not create a node per cell or retain a live link to the source asset.

Original examples in `prefabs/`: a 468-cell brick cottage, 46-cell stair flight, 32-cell doorway wall and 398-cell tower floor. Regenerate them with `python tools/generate_prefabs.py`. Tower floors repeat every four metres vertically, with an open stair shaft connecting storeys; twelve floors contain 4,776 cells. These are editable architectural examples with open window apertures, not finished assets with glass, doors or furnished interiors.

In the terrain scene, **B** selects block mode, **P** cycles prefab assets and single-block mode, **R** rotates, and **RMB** places. **1–6** returns to individual shapes. A green/red bounds outline indicates whether placement passes occupancy, player-clearance and capacity checks. The outline updates at 10 Hz and caches native validation until its anchor, rotation, selected asset or block data changes. Clicking revalidates before placement. Prepare suitable ground first: prefab placement does not grade terrain or automatically extend foundations. The editor uses non-replacing placement; removal still edits individual blocks.

Prefab capture has a native API but no selection/save dialog yet. Static-model composition, instance-level selection and prefab-linked updates remain pending. See [prefab validation](../../docs/PREFAB_VALIDATION.md) for native and graphical evidence.

### Bounded construction history

Static model edits use a separate native `NativeStaticHistory` journal. Configure
it with an array of distinct `NativeStaticBatch` collections, a retained-record
byte budget (0–64 MiB), and a step cap (0–1,024). Registration holds weak object
identities and accepts at most 256 collections. `insert(collection, transform,
protected_bounds)`, `erase(collection, id)` and `update(collection, id, transform,
protected_bounds)` record fixed-size before/after transform deltas. Model IDs are
preserved on replay. `undo(protected_bounds)` and `redo(protected_bounds)` follow
one chronological timeline across all registered model assets. These are
scene-thread authoring APIs; they do not record terrain or block commands.

The demo model catalog uses 1 MiB / 256 steps. In M mode, **Ctrl+Z** undoes and
**Ctrl+Y** or **Ctrl+Shift+Z** redoes placement/removal, with player protection.
The UI displays available step counts. Selection buttons and keyboard increments
use native transform update history; drag handles remain pending.

The shared record budget covers undo and redo, excluding deque allocator overhead
and the separately bounded registry. `stats()` reports `record_bytes`,
`record_size`, limits, step counts, external-change barriers and unrecorded edits.
The oldest undo commands are retired at capacity. Rejected/no-op edits preserve
redo; accepted new edits discard it. Zero limits or a budget smaller than one
record allow edits but retain no history. Valid reconfiguration clears history;
invalid reconfiguration leaves it intact.

External placement edits, mesh replacement, bulk replacement, valid snapshot
restoration (even identical bytes), or destruction of a registered collection
invalidate the entire model timeline at the next command/status query. Failed or
net-zero external updates do not. This prevents stale undo from overwriting
loaded or independently authored data. Collection transforms and collision-only
configuration do not change local authored records; replay uses their current
world frame and compound parts for player protection. History is not serialized.

Journal state commits before `changed` notifications. Reentrant journal commands
are rejected during notification; external callback mutations are detected and
invalidate history afterward. Replay uses the normal incremental batch edit path
so render groups, physics, vegetation exclusion and save invalidation stay in
sync. This is local editor history, not a multiplayer command protocol.

History is opt-in: `configure_history(byte_limit, step_limit)` enables native undo/redo for subsequent `set_cells` and `place_prefab` calls. Both demos use 16 MiB of retained cell-record capacity and 128 commands. Runtime-only worlds default to disabled history. Limits may be 0–64 MiB and 0–1,024 commands; either zero disables history and releases its retained records. Invalid limits leave the prior configuration intact.

Each successful edit is one command containing unique changed coordinates and their before/after values, at 16 bytes per cell. Duplicate input coordinates retain the original value and final write; net-zero and rejected edits do not consume a command or erase redo. New mutations discard the abandoned redo branch. The shared byte/step budget covers both undo and redo stacks. Eviction removes the oldest undo commands first, then the farthest future redo commands. An accepted edit larger than the configured byte budget clears history as a barrier; it cannot be partially undone or crossed by older undo commands. The demos' default budget can retain any single valid edit.

`undo(protected_bounds=AABB())` and `redo(...)` return success and use the same native chunk edit path as forward changes. Occupancy, bake tickets, nearby collision, change signals and persistence invalidation are updated together. Optional positive-volume world-space bounds reject restoration of any occupied cell intersecting that volume; zero size disables this guard. Partial block shapes conservatively reserve their entire cell. The terrain editor passes its player volume. Stack changes finish before emitting `changed`, so listeners see the committed history state.

`can_undo()`, `can_redo()`, `history_stats()` and `clear_history()` support editor integration. `cell_capacity_bytes` accounts for allocated cell-vector capacity, not total allocator/deque overhead. Metadata is separately bounded by the command cap. Per-edit staging and sort scratch are temporary and are not included in the retained-history budget. `unrecorded_edits` counts oversized accepted edits for the node's lifetime. History is ephemeral and excluded from world snapshots: successful restoration clears the timeline, while failed restoration preserves it. Editing and history mutation are scene-thread operations.

In block mode, **Ctrl+Z** undoes; **Ctrl+Y** or **Ctrl+Shift+Z** redoes. The standalone structure editor uses the same shortcuts. These commands cover blocks and whole block-prefab placements, not terrain, water or static-model edits. Cross-addon and multiplayer-authoritative history remain pending. See [history validation](../../docs/BUILDING_HISTORY_VALIDATION.md).

For combined world saves, use `structures_world.gd`. Call `prepare()`, register each application-resolved mesh with `register_model(asset_key, mesh)`, then register its `capture_snapshot`, `restore_snapshot`, `snapshot_validator()` and `empty_snapshot()` methods with `world_runtime/world_persistence.gd` before terrain startup. `blocks` exposes the native block world; `model(asset_key)` returns its native placement collection. Registration locks each collection's asset identity. Sealing the validator freezes the registry; subsequent registration fails. The adapter itself has no dependency on terrain and can capture/restore standalone bundles too.

`NativeStructuresSnapshot` stores the block snapshot and sorted model snapshots in one checksummed `TFSB` bundle, bounded to 64 MiB and 256 asset collections. Unknown assets fail validation before any scene state changes. Newly registered assets missing from older saves restore empty. The adapter caches unchanged serialized data, duplicates public byte arrays, and stops capture assembly when the byte budget is exceeded. The global archive now supports 64 MiB per addon section; oversized live captures leave the old file intact and saving can recover after the live data is corrected. This remains whole-world snapshot storage, with main-thread capture/restore costs; region streaming and journals are pending.

The terrain demo uses this adapter for F5/F9 and orderly shutdown. Its B mode edits native blocks independently of terrain and the existing player collides with them. Main-world static placement data is saved for registered meshes; M opens the model catalog and placement tool. The ecosystem coordinator now excludes tree volumes from occupied block cells and restores eligible trees after demolition. Registered static models now participate through their compound proxy bounds (or mesh bounds without configured proxies). Buildings rebake after loading; explicit high-speed collision readiness is also unfinished.

`overlap_mask(Array[Transform3D], AABB)` accepts world-space instance transforms and a prototype-local bound. It returns one byte per instance (1 intersects occupied cells, 0 clear), or an empty array on invalid input. Batches are limited to 65,536 instances. All shapes reserve their entire occupied cell. A derived 16-bit Y mask per XZ column adds 512 bytes per resident chunk (at most 1 MiB); it updates atomically with edits and is reconstructed from snapshot cells. Queries choose between intersecting chunk lookups and scanning the bounded resident chunk set. No tree-specific logic or dependencies enter this addon.

The block world's `capture_snapshot`, `validate_snapshot`, and `restore_snapshot` implement a versioned, sorted, RLE block format with SHA-256 integrity validation. Loads are bounded and validated before replacing data; restoration invalidates outstanding bakes. The separate `demo/structures.tscn` showcase still uses its basic block-only F5/F9 file; its example static props regenerate at startup. It does not use the terrain demo's compound save path.

The addon supplies editable block buildings, reusable block prefab assets, bounded block undo/redo, nearby mesh residency with memory bake reuse and persistent static placement data. Authoritative region eviction, disk bake caches, distant building LOD/HLOD, transparent windows, doors, combined block/model prefabs, cross-addon command history, city generation, multiplayer authority and long-duration performance validation remain open. The demo keeps authored building cells resident up to the explicit capacity; explicit native region transfers are available as described below. It must not be described as a production city engine.

## Authored region storage

The native block world supports explicit 64-cell region packets with conditional capture/unload/reload, missing-region readiness and save guards. See [Block region transfers](../../docs/BLOCK_REGION_TRANSFERS.md) for the API and format. The independent `NativeBlockRegionStore` adds conditional batch disk publication, explicit backup recovery and bounded garbage collection; see [Block region catalog](../../docs/BLOCK_REGION_CATALOG.md). Its synchronous C++ API can run on a caller-owned I/O worker. [NativeBlockRegionIO](../../docs/BLOCK_REGION_IO.md) supplies a persistent native worker with bounded request and completion reservations, FIFO tickets and drain-on-stop ownership. Automatic travel paging and catalog-aware compound saves are not enabled in the demo.
# Street-frontage prefab composition

`NativeBlockPrefab.compose_frontage(sources, lots_per_side, street_width, gap, seed)`
creates a deterministic pair of building rows using the existing prefab format.
Source building fronts must face local +Z. The opposite row rotates by two
quarter turns; each source's lower bound is aligned to ground Y=0, including
assets with nonzero or negative local origins. Lots progress along +X, using the
larger footprint of each facing pair plus the requested gap. The street is
centered on Z=0 and remains empty, with an additional gap on each side.

Limits: 1–64 lots per side, 1–256 nonempty sources, even street width 4–64,
gap 1–32, unsigned 32-bit seed, and the existing 262,144-cell / ±4095-coordinate
prefab limits. Version-1 building choice uses a fixed ordinal hash, independent
of engine RNG state. Invalid or oversized compositions preserve the previous
prefab. The result can use normal prefab placement, conflict checks and block
world persistence. It does not stamp asphalt, grade terrain, validate support,
generate navigation or provide a complete settlement editor. Those integration steps
remain required before treating this as a complete town generator.

In the construction palette, select a building prefab, enter a new prefab name,
and choose **Create street frontage from selected prefab**. Set buildings per
side, even street width and gap, then create and save. The result enters the
personal prefab library and is selected for ordinary preview/placement. This
authors the building layout only; prepare suitable terrain and roads separately.

## Foundation sampling

NativeBlockPrefab.foundation_samples(origin, quarter_turns, max_base_y) returns
world-space column-centre probes 0.25 m below each selected lowest cell. The
lowest cell per X/Z column is cached during successful asset configuration;
queries traverse the footprint, not every building floor. max_base_y is an
explicit local-space foundation band ceiling, preventing roof eaves and
balconies from being treated as ground-bearing columns. Use 0 for normalized
frontages; stepped foundations require an authored band that includes their
base heights. Rotation matches integer block placement. Invalid rotation or
out-of-range origin/band returns an empty array. Empty is not proof of support.

These are screening probes, not structural analysis or full contact coverage.
The world editor checks frontage-tagged prefabs before placement, in bounded worker batches. Ordinary modular prefabs are not subject to this ground-only rule. Terrain
queries must use a consistent revision and placement must revalidate before
commit; a result from older terrain cannot authorize a later placement.

Frontage placement uses the normalized local base Y=0. Amber preview bounds
indicate that ground support is checked on placement. Unsupported sites need
grading first. Changing selection or rotation cancels pending placement;
terrain changes require a fresh check. No terrain-interior clearance or
structural stability guarantee follows from foundation centre probes.

## Frontage terrain clearance

After foundation support, frontage placement checks native column envelopes
above local base Y=0. Each occupied X/Z column spans from its lowest cell
(clamped to Y=1) through its highest cell, so enclosed room space between
floor and roof is included. Empty street columns are excluded.
clearance_sample_count reports the probe count; clearance_samples returns
at most 512 probes from a numeric cursor. Prefix-indexed column spans avoid
allocating a full voxel volume and avoid rescanning previous samples.

This is conservative voxel-lattice screening, not exact triangle intersection
or a guarantee for arbitrary authored spaces without floor/roof columns.
Supported and clear must share the same terrain revision before placement.

Frontage editor authoring uses begin_frontage/poll_frontage: one low-priority
worker receives captured source records, builds private native resources and
saves the result. Main-thread completion publishes it to the library. Call
shutdown_frontage before releasing the library while work is outstanding; it
joins and removes unpublished output. The demo connects this to tree exit.
The synchronous frontage API remains available for offline tools/tests.

Frontage validation also checks every voxel layer through the maximum 8 m
grading-fill depth, clamped at low altitude toward protected bedrock. Native
column queries reject isolated slabs and intermediate air pockets. This is
sampled-column continuity, not lateral stability or deeper structural analysis.

Foundation checks assemble at most eight native 512-point pages per
request_density_scan (4096 samples). Scans share the terrain batch reservation
and revision checks, reducing repeated waits behind background meshing. A failed
page discards all values from that scan; placement still requires every support
and clearance scan to succeed at the captured terrain revision.

In the world construction panel, select a prefab, aim at nearby terrain and
choose Survey ground for selected prefab. The read-only dialog reports the
captured origin/rotation and a proposed base height for up to 8 m fill and 12 m
cut. Use the survey dialog to prepare the stone foundation, or grade manually. Natural-surface surveys cannot reconstruct
arbitrary edited terrain; frontage placement still performs its support and
interior-clearance checks.

site_plan.gd foundation(asset, origin, rotation, grade) returns bounded grading
segments and their combined protection AABB for a normalized local-Y=0 layout.
It covers the rectangular site, including gaps, with stone fill and shoulders.
It performs no edits. Callers must validate the complete protection envelope
against the player, vehicles and structures before applying any segment.
The survey dialog can apply the plan through site_preparation.gd.

Site preparation checks the whole expanded plan against the player, vehicle
and structures before starting and between native edits. Stop or close the
dialog to stop after the accepted edit completes. Completed terrain edits
remain; resume applies only remaining sections at the same terrain revision.
This in-memory workflow has no terrain undo or recovery across reload. It
does not pave streets or place buildings, and frontage support checks remain
mandatory after grading.
