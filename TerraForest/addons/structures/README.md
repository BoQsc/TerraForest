# Native block structures and static models

Independent Godot 4.7 Windows x86-64 addon. Copy this directory into a project; the GDExtension registers `NativeBlockWorld` and `NativeStaticBatch`. No terrain, vegetation or other TerraForest addon is required. Native sources and both debug/release DLLs are included. Build using the repository's pinned Zig/prebuilt godot-cpp toolchain:

```text
python tools/build_native.py --addon structures --target all
```

## Representation and editing

`NativeBlockWorld` is a Node3D with sparse 16×16×16 cell chunks. Each cell is a 16-bit word; a resident chunk's cell payload is 8 KiB. A cell is one local metre. Translation/rotation can be applied to the world node; supply focus in that node's local coordinates. Nonuniform scaling is not a supported physics configuration. There is no node per block.

`set_cells(PackedInt32Array)` accepts `[x,y,z,word, ...]`, up to 262,144 records. Coordinates are signed integers in ±1,048,575. Word zero erases. Nonzero words encode `shape | (rotation << 3) | (material << 5)`:

| Field | Values |
| --- | --- |
| Shape | 1 cube, 2 lower half slab, 3 four-step staircase, 4 planar slope, 5 centred half-width post |
| Rotation | 0–3 quarter turns about Y |
| Material | 0 brick, 1 wood, 2 concrete, 3 metal |

The entire batch is validated and staged before modification; repeated coordinates use their final value. Invalid input or exceeding the 2,048 resident chunk capacity leaves the world unchanged. Empty chunks are reclaimed. Authoring methods and snapshot capture/restore run on the main thread. `validate_snapshot` reads only its argument and can run on a worker. General concurrent authoring is not supported.

## Baking and rendering

Changes invalidate the edited chunk and resident face neighbours. One native worker receives an immutable 18³ cell halo, generates geometry without accessing Godot objects, and returns plain buffers. Main-thread publication checks a dependency ticket and rejects obsolete work. At most one nonempty mesh is published per frame. A repeated edit deduplicates pending work; abandoned empty chunks do not leave historical queue entries.

Quarter-cell occupancy is temporary bake scratch space for exact slab, stair and post joins. Greedy face merging removes hidden boundaries and combines coplanar regions of the same material, including across block edges. Chunk boundaries hide internal faces but do not merge separate chunk meshes. Slopes use an exact planar wedge; wedge boundaries currently use conservative geometry and are not greedily merged or clipped against neighbours.

Each occupied visual chunk is one ArrayMesh surface with a texture array. Four original deterministic 128² tile textures and their independent mip chains are generated once per world. Repeating UVs preserve material detail across merged faces. These are basic procedural materials, not a finished PBR asset library.

Nearby chunk collision uses the same triangles as rendering, on layer **2**. `set_focus(Vector3)` and `set_collision_radius(metres)` control residency; radius defaults to 48 and accepts 0–256. One new collision shape is created per frame, with distant bodies released. Collision range uses chunk centres plus a conservative 14 m extent. This bounds normal physics work, but high-speed collision readiness and nearest-first shape creation still need a dedicated traversal policy. Mesh upload/collision construction for one complex chunk can still spike a frame; publication has a count budget, not a measured time budget.

`flush_bakes()` deliberately blocks for offline baking/tests. Do not call it from a live gameplay frame loop. `stats()` reports cell payload, resident chunks, triangles, pending work and rejected stale bakes.

### Mesh residency and bake reuse

`configure_streaming(enabled, radius, chunk_limit, mesh_byte_limit, cache_byte_limit)` opts into nearby mesh residency. The terrain demo uses a 384 m radius, 256 visual chunks, 64 MiB of mesh payload and 32 MiB of retained native bake buffers. The standalone addon defaults to nonstreamed authoring. Valid limits are radius 16–4,096 m, 1–2,048 visual chunks, 64 KiB–512 MiB of mesh payload and 0–512 MiB of bake cache. Invalid configurations preserve the previous settings; zero cache bytes disables reuse.

The native scheduler selects the nearest authored chunks within the radius plus a conservative 14 m chunk extent. It refreshes after edits/configuration changes or at least 8 m of focus movement, instead of scanning the world every idle frame. Leaving the selected set releases meshes and their physics bodies while preserving authored cells. A least-recently-used memory cache retains dependency-validated bake buffers; returning publishes cached geometry without another worker job. Edits invalidate the changed chunk and its face neighbours. Snapshot restoration clears cached geometry. A worker finishing outside the selected set may populate the cache without uploading a distant mesh.

Both worker and cached results share the one-nonempty-upload-per-frame limit. Mesh admission prefers nearby chunks and evicts farther meshes when needed. A chunk too large for the mesh budget stays deferred instead of rebaking every frame. `streaming_stats()` exposes mesh payload bytes, retained cache capacity, cache hits, worker launches, evictions, wanted/deferred chunks and `budget_blocked_chunks`. The demo displays a detail-limit notice when admission is blocked. `is_idle()` means no pending residency/bake work; it does **not** guarantee that budget-blocked geometry or player collision is available.

The mesh budget counts uploaded vertex attributes and indices, not complete VRAM, driver, ArrayMesh, material or physics memory. Cache accounting includes vector capacity, but excludes container metadata and transient worker scratch. Eviction runs on a residency refresh without a wall-time budget. Authoritative cells still remain in RAM, capped at 2,048 chunks; persistence remains whole-world snapshots. This is render/near-physics streaming with an in-memory bake cache. Disk region storage, distant building LOD and high-speed collision readiness remain pending. See [streaming validation](../../docs/BUILDING_STREAMING_VALIDATION.md).

## Static models

`NativeStaticBatch.set_instances(mesh, transforms)` accepts any Godot Mesh, including one extracted from an imported model. Transforms use Godot's 12-float MultiMesh row layout:

```text
xx xy xz origin_x   yx yy yz origin_y   zx zy zz origin_z
```

The native implementation validates finite, nonsingular transforms, partitions origins into signed 32 m spatial groups, shares the source mesh, and bulk uploads one MultiMesh per group. The limit is 100,000 instances and 4,096 groups per collection. An empty input clears the collection. This replacement API assigns IDs 1 through N in input order; use the incremental API below when identity must survive edits. Large models crossing group bounds retain their full rendering bounds but should use a suitable grouping/LOD strategy.

### Stable placements

Configure a collection with `configure_asset("architecture/fence/v1", mesh)`. The printable ASCII key (1–128 bytes, no spaces) identifies the application-resolved mesh; snapshots never load resource paths supplied by a file. A populated collection cannot switch to a different key. The same key may be rebound to a replacement Mesh, for example after an application-approved asset reload.

`upsert_instances(ids, transforms)` accepts positive signed 64-bit IDs and the same 12-float transforms. Existing IDs move; new IDs insert. Duplicate IDs, invalid transforms and capacity violations reject the whole transaction. Small edits within a spatial group update individual MultiMesh slots, with no full-buffer upload. More than 64 changed placements in a group use a bulk upload. Insertions, removals and cross-group moves rebuild only affected groups; unrelated scene nodes and buffers are retained. Identical edits cause no upload. Capacity is validated against the final state, so moving a singleton group at the group limit is allowed.

`remove_instances(ids)` requires unique existing IDs and rejects the entire operation if any are missing. `get_ids()` returns sorted IDs, and `get_instance(id)` returns the 12-float authored transform, or an empty array when missing. IDs are scoped to this asset collection and assigned by the caller; global authority and ID allocation are application responsibilities. Mutation, capture and restore APIs are main-thread operations.

`capture_snapshot()` emits a versioned little-endian format containing the asset key, sorted IDs, float32 transforms and SHA-256 checksum. Configure a matching asset before restoration. `validate_snapshot()` validates only its byte argument and may run on a worker; `restore_snapshot()` also checks the configured asset identity before changing the collection. Input size, count, ordering, transform validity and spatial group limits are checked. Unconfigured collections return an empty byte array instead of saving an anonymous mesh. Snapshots preserve placement data, not Mesh resources. The application must resolve asset keys consistently on load.

Placement records, group membership and GPU slot indices now remain in native memory. The `transform_bytes` statistic reports only the 48-byte transform payload per object, not total CPU/GPU memory or map overhead. Bulk initialization consequently does more work than the earlier renderer-only API; current regression evidence records this separately. Collision proxies, network replication, automatic region eviction and durable journal storage remain pending.

## Saves and present scope

### Reusable block prefabs

`NativeBlockPrefab` is a native Godot `Resource`. `configure(PackedInt32Array)` accepts occupied `[x,y,z,word]` records, validates them atomically, rejects duplicate coordinates, and sorts them for deterministic serialization. The shape/material words match `NativeBlockWorld`. Limits are 262,144 cells per asset and local coordinates from -4,095 to 4,095. `get_records()` returns independent data; empty assets are allowed for authoring but cannot be placed. Godot `ResourceSaver`/`ResourceLoader` support `.tres` files directly through the `records` property.

`can_place_prefab(asset, origin, quarter_turns, replace=false)` validates the complete destination against coordinate and world chunk limits. `place_prefab(...)` performs the same validation and commits all cells together through the native chunk edit path, emitting one logical change signal. The default rejects occupied destination cells. Explicit `replace=true` overwrites only listed cells; unlisted cells inside the bounding box remain untouched. Rotations 0–3 turn cell coordinates `(x,z)` to `(-z,x)` and rotate stair/slope orientation as well. The pivot is the centre of local cell `(0,0,0)`. `asset.placement_bounds(origin, turns)` returns the matching local-world cell bounds.

`capture_prefab(origin, size)` extracts existing block cells into a new resource, with origin-relative coordinates. Each dimension is 1–256 and the selection volume is limited to 262,144 cells. Invalid selections return null. The caller can name and save the resource. Capture and placement are native authoring operations, not per-frame world scans. Placed prefabs become ordinary editable cells and use existing chunk meshing, collision, vegetation exclusion and compound world persistence; they do not create a node per cell or retain a live link to the source asset.

Original examples in `prefabs/`: a 468-cell brick cottage, 46-cell stair flight, 32-cell doorway wall and 398-cell tower floor. Regenerate them with `python tools/generate_prefabs.py`. Tower floors repeat every four metres vertically, with an open stair shaft connecting storeys; twelve floors contain 4,776 cells. These are editable architectural examples with open window apertures, not finished assets with glass, doors or furnished interiors.

In the terrain scene, **B** selects block mode, **P** cycles prefab assets and single-block mode, **R** rotates, and **RMB** places. **1–5** returns to individual shapes. A green/red bounds outline indicates whether placement passes occupancy, player-clearance and capacity checks. The outline updates at 10 Hz and caches native validation until its anchor, rotation, selected asset or block data changes. Clicking revalidates before placement. Prepare suitable ground first: prefab placement does not grade terrain or automatically extend foundations. The editor uses non-replacing placement; removal still edits individual blocks.

Prefab capture has a native API but no selection/save dialog yet. Static-model composition, instance-level selection and prefab-linked updates remain pending. See [prefab validation](../../docs/PREFAB_VALIDATION.md) for native and graphical evidence.

### Bounded construction history

History is opt-in: `configure_history(byte_limit, step_limit)` enables native undo/redo for subsequent `set_cells` and `place_prefab` calls. Both demos use 16 MiB of retained cell-record capacity and 128 commands. Runtime-only worlds default to disabled history. Limits may be 0–64 MiB and 0–1,024 commands; either zero disables history and releases its retained records. Invalid limits leave the prior configuration intact.

Each successful edit is one command containing unique changed coordinates and their before/after values, at 16 bytes per cell. Duplicate input coordinates retain the original value and final write; net-zero and rejected edits do not consume a command or erase redo. New mutations discard the abandoned redo branch. The shared byte/step budget covers both undo and redo stacks. Eviction removes the oldest undo commands first, then the farthest future redo commands. An accepted edit larger than the configured byte budget clears history as a barrier; it cannot be partially undone or crossed by older undo commands. The demos' default budget can retain any single valid edit.

`undo(protected_bounds=AABB())` and `redo(...)` return success and use the same native chunk edit path as forward changes. Occupancy, bake tickets, nearby collision, change signals and persistence invalidation are updated together. Optional positive-volume world-space bounds reject restoration of any occupied cell intersecting that volume; zero size disables this guard. Partial block shapes conservatively reserve their entire cell. The terrain editor passes its player volume. Stack changes finish before emitting `changed`, so listeners see the committed history state.

`can_undo()`, `can_redo()`, `history_stats()` and `clear_history()` support editor integration. `cell_capacity_bytes` accounts for allocated cell-vector capacity, not total allocator/deque overhead. Metadata is separately bounded by the command cap. Per-edit staging and sort scratch are temporary and are not included in the retained-history budget. `unrecorded_edits` counts oversized accepted edits for the node's lifetime. History is ephemeral and excluded from world snapshots: successful restoration clears the timeline, while failed restoration preserves it. Editing and history mutation are scene-thread operations.

In block mode, **Ctrl+Z** undoes; **Ctrl+Y** or **Ctrl+Shift+Z** redoes. The standalone structure editor uses the same shortcuts. These commands cover blocks and whole block-prefab placements, not terrain, water or static-model edits. Cross-addon and multiplayer-authoritative history remain pending. See [history validation](../../docs/BUILDING_HISTORY_VALIDATION.md).

For combined world saves, use `structures_world.gd`. Call `prepare()`, register each application-resolved mesh with `register_model(asset_key, mesh)`, then register its `capture_snapshot`, `restore_snapshot`, `snapshot_validator()` and `empty_snapshot()` methods with `world_runtime/world_persistence.gd` before terrain startup. `blocks` exposes the native block world; `model(asset_key)` returns its native placement collection. Registration locks each collection's asset identity. Sealing the validator freezes the registry; subsequent registration fails. The adapter itself has no dependency on terrain and can capture/restore standalone bundles too.

`NativeStructuresSnapshot` stores the block snapshot and sorted model snapshots in one checksummed `TFSB` bundle, bounded to 64 MiB and 256 asset collections. Unknown assets fail validation before any scene state changes. Newly registered assets missing from older saves restore empty. The adapter caches unchanged serialized data, duplicates public byte arrays, and stops capture assembly when the byte budget is exceeded. The global archive now supports 64 MiB per addon section; oversized live captures leave the old file intact and saving can recover after the live data is corrected. This remains whole-world snapshot storage, with main-thread capture/restore costs; region streaming and journals are pending.

The terrain demo uses this adapter for F5/F9 and orderly shutdown. Its B mode edits native blocks independently of terrain and the existing player collides with them. Main-world static placement data is saved for registered meshes, but a model catalog/placement UI is still pending. The ecosystem coordinator now excludes tree volumes from occupied block cells and restores eligible trees after demolition. Static model collections do not yet reserve vegetation space. Buildings rebake after loading; explicit high-speed collision readiness is also unfinished.

`overlap_mask(Array[Transform3D], AABB)` accepts world-space instance transforms and a prototype-local bound. It returns one byte per instance (1 intersects occupied cells, 0 clear), or an empty array on invalid input. Batches are limited to 65,536 instances. All shapes reserve their entire occupied cell. A derived 16-bit Y mask per XZ column adds 512 bytes per resident chunk (at most 1 MiB); it updates atomically with edits and is reconstructed from snapshot cells. Queries choose between intersecting chunk lookups and scanning the bounded resident chunk set. No tree-specific logic or dependencies enter this addon.

The block world's `capture_snapshot`, `validate_snapshot`, and `restore_snapshot` implement a versioned, sorted, RLE block format with SHA-256 integrity validation. Loads are bounded and validated before replacing data; restoration invalidates outstanding bakes. The separate `demo/structures.tscn` showcase still uses its basic block-only F5/F9 file; its example static props regenerate at startup. It does not use the terrain demo's compound save path.

The addon supplies editable block buildings, reusable block prefab assets, bounded block undo/redo, nearby mesh residency with memory bake reuse and persistent static placement data. Authoritative region eviction, disk bake caches, distant building LOD/HLOD, transparent windows, doors, combined block/model prefabs, cross-addon command history, city generation, multiplayer authority and long-duration performance validation remain open. All authored building cells currently remain resident up to the explicit capacity. It must not be described as a production city engine.
