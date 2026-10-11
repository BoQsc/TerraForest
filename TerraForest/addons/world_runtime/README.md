# World Runtime native addon

Typed C++ GDExtension built with Zig 0.16.0 and the pinned prebuilt godot-cpp API 4.7 package. No GDScript simulation loop is included. `NativeEntityStore` provides batched kinematics. `NativeWorldArchive` provides bounded versioned snapshots, SHA-256 validation, an exclusive Windows save lease and atomic file publication; `world_persistence.gd` supplies registration and scene configuration callbacks. See `docs/WORLD_STORAGE.md` for format, threading and recovery details.

Copy this addon directory, including `bin` and `world_runtime.gdextension`, into a Godot 4.7 Windows x86-64 **single-precision** project. Godot registers the native class when the extension is loaded. For direct script runners without an editor import, load the `.gdextension` through `GDExtensionManager` first.

```gdscript
# Support/API calls only; every entity update is implemented in C++.
var store = ClassDB.instantiate("NativeEntityStore")
store.configure(100000)
var ids = store.spawn_grid(100000, Vector3.ZERO, 2.0, Vector3(12, 0, 0))
store.step(1.0 / 60.0)
var transforms = store.multimesh_transforms()
```

`configure(capacity)` accepts 1–262,144 and rejects reconfiguration while entities are live. `spawn(position, velocity)` returns a positive generation-checked handle or zero on failure. `spawn_grid(...)` performs a bounded native batch. `despawn`, `contains`, `get_position` and `set_velocity` operate on handles; use `contains` when an invalid handle's zero-position fallback would be ambiguous.

`step(seconds)` accepts finite durations in (0, 0.1]. It integrates constant velocity and maintains a 32-unit spatial grid. Slot links are preallocated; entering a previously empty spatial cell can allocate a hash-map entry. This is **kinematics**, not a collision/physics/vehicle solver. Nonfinite inputs and overflow-producing ticks are rejected before mutation. Handles do not alias recycled slots or reconfigured pools; after the positive generation namespace is exhausted, spawning fails instead of wrapping.

Ticks iterate a preallocated dense set of nonzero-velocity entities. Exact zero
velocity removes an entity from that set; changing velocity wakes it in O(1).
Stationary entities remain in spatial queries, rendering and saves. Restoring a
snapshot reconstructs moving membership from velocity without changing the save
format. `moving` reports current moving membership; `last_step_visited` reports
the number examined in the most recent tick's overflow preflight (zero for an
invalid duration). Successful ticks perform a second pass over those movers.
This is not contact-based physics sleeping or distance-based simulation LOD.

`query_sphere(center, radius, result_limit=256, candidate_budget=4096)` returns
`ok`, `complete`, generation-checked `ids`, `visited` candidate count and
`cells_visited`. Queries support finite centers within ±10,000,000 per axis,
radius 0–1,024, result limits 1–4,096 and candidate budgets 1–16,384. A footprint
over 4,096 grid cells is rejected with `reason="region_too_large"`. Dense queries
return `complete=false` and `reason="result_limit"` or `"candidate_budget"`;
callers must handle this explicitly, for example by reducing the query region.
Results are neither nearest-first nor a stable ordering, and there is no paging
cursor. Spatial cells are created on demand and removed when empty. Query limits
do not change the existing unrestricted finite-position storage contract.
`pool_bytes` covers preallocated slots and arrays; it excludes hash-map allocation
overhead. Use `spatial_cells` to observe occupied cell count. The store is owned
by one caller thread; concurrent mutation/query access is unsupported.

`query_sphere_nearest` accepts the same arguments and limits. It scans up to the
candidate budget and retains at most result_limit candidates in a native heap,
then returns distance order, breaking ties by persistent identity. It does not
stop scanning when the result limit fills. `selection_complete=true` means the
entire query footprint was searched and the returned nearest subset is proven;
`complete=false` can still indicate additional entities omitted by result_limit.
If candidate_budget is exhausted, selection_complete is false: results are only
nearest among visited candidates. Cells retain the ordinary traversal order.
Temporary heap storage is bounded by result_limit; this is not paging or LOD.

`multimesh_transforms()` produces one 12-float-per-instance buffer in dense live order. It does not submit GPU work. Use that output with a 3D MultiMesh configured without color/custom data. Dense order can change after removals; it is not a persistent entity ID. `statistics()` reports capacity, live count, ticks and reserved pool bytes.

Entity storage uses `capture_storage_snapshot()`, `validate_snapshot(data)` and
`restore_storage_snapshot(data)`, compatible with `world_persistence.gd` component
registration. Configure the pool before capturing its empty/default snapshot.
The version 2 format is little-endian: four u32 fields (magic `0x31454654`, version 2,
capacity, live count), a u64 next-identity cursor, then 32-byte live rows: a u64
persistent identity followed by six float32 values (position xyz, velocity xyz),
in dense order. Maximum size is 8,388,632 bytes. Version 1 snapshots remain readable;
their rows receive deterministic identities 1 through count on migration. Validation rejects
invalid counts, nonfinite values, unknown versions and extra/truncated bytes.
The enclosing world archive supplies integrity checking; the raw section has no
checksum. Validation reads only its input and may run on the save worker.

Restore stages a replacement pool/index before publication, resets the simulation
tick count and invalidates all previous handles by assigning fresh generations.
It preserves positions, velocities and persistent identities exactly, but does not persist
archetypes, animation, inventory or network authority. Refresh renderers after
restore. Capture/restore belong to the store-owning thread. Restore temporarily
holds both pools, and whole-population capture/restore are synchronous; region
paging and incremental capture are not implemented. An unconfigured capture
returns empty bytes, which is not a valid snapshot.

`persistent_id(handle)` returns an entity's store-local positive identity, or zero
for an invalid handle. `resolve_identity(identity)` returns the current runtime
handle, or zero for a missing identity. IDs increase monotonically within the
saved timeline and are not reused after despawn or empty reconfiguration. Snapshot
reload restores that timeline's allocation cursor, so references to entities created
after an older save must be discarded when rolling back. IDs are not globally unique
across worlds or stores; cross-store/network references must include their namespace.
Duplicate, zero and out-of-cursor snapshot IDs are rejected. Exhaustion fails spawning
instead of wrapping. The identity hash index allocates per entity; `pool_bytes`
excludes both identity-index and spatial-index allocations.

`NativeEntityRenderer` is a main-thread `MultiMeshInstance3D` adapter. Call
`configure(store, mesh, capacity)` with capacity 1–4,096, then
`refresh(center, radius, candidate_budget=4096)` after simulation as needed.
Positions and centers use the renderer's local coordinate system. It submits a
fixed `capacity * 48` byte transform buffer only when a selected transform row
changes, with only the returned rows visible. Unchanged selections reuse the
retained buffer without writable-array detachment or GPU transform upload.
Queries and bounded row comparisons still run on each refresh.
Empty/invalid queries hide previous instances without
uploading a buffer. It does not automatically simulate or refresh.

Refresh returns the spatial query fields plus `rendered` and `upload_bytes`.
The renderer uses query_sphere_nearest. Truncation is explicit; inspect
selection_complete before assuming globally nearest selection. This is not LOD,
occlusion or fair admission across overcrowded cells. One renderer shares one mesh and has
aggregate MultiMesh culling; partitioning by archetype/region remains caller work.
Do not modify its owned MultiMesh; detected layout/replacement changes fail closed
and require reconfiguration. Use the supplied mesh/material for appearance.
There are no per-entity nodes, rotations, animation or scale channels yet.
See `tests/entity_renderer.gd` for setup and lifecycle examples.

All store access is owned by one simulation thread. When using the renderer,
that must be the main thread too; do not mutate the store concurrently with
refresh. Handles are local to their store instance. Multiplayer authority,
network IDs/replication, collision, AI and vehicle systems remain future integrations.

Build from the repository using `python tools/build_native.py --target all`. The full build contract and upgrade policy are in `docs/NATIVE_DEVELOPMENT.md`. Keep the bundled godot-cpp MIT notice when redistributing linked binaries.

`material_pickups.gd` connects four static supply types (101 brick, 102 wood,
103 concrete, 104 metal) to native stores and renderers. `prepare(persistence)`
registers four compound-save sections before terrain attachment. `spawn(item,
local_position)` authors one collectible unit and returns its persistent ID; it
does not add gravity or collision bodies. Keep the coordinator unscaled. Each
type starts with capacity 4,096 and a 256-instance renderer refreshed at 10 Hz
within 64 m; `render_status` exposes truncation. Gameplay collection is an explicit
E action within 2.5 m, with terrain/building line-of-sight and inventory capacity
checks. The inventory displays stack counts and prevents materials being equipped
as tools. Fly mode keeps its existing controls. The world includes these save
providers, but does not automatically seed supplies or generate demolition loot.
The construction palette includes a supply material selector and **Place supply
at aim** button. Aim at a supporting surface, release the mouse with Esc and click
the button. Placement requires nearby building collision to be ready and rejects
physical obstruction or another supply within 0.5 m. These editor-authored supplies
are free placement; block undo/redo does not modify them. Collect supplies with E
to remove them. Physical settling, crafting/build-cost consumption and a survival
economy are still missing. Supplies can become unsupported after terrain edits.
Interaction examines at most 64 candidates per type on keypress and fails visibly
if query budgets are exceeded. This is not a multiplayer-authoritative transaction.

NativeRoadAnchors validates the optional road_anchors compound-save section.
Empty means no prepared street. Version 1 is exactly 64 bytes: magic TRA1,
u32 version 1, six little-endian f64 endpoint coordinates, then f64 width.
Version 2 stores a bounded catalog: a 16-byte header (magic, version, count,
selected index) and 1..256 version-one records. Maximum size is 16400 bytes.
Legacy single-street records remain readable. Neither format certifies current
terrain validity or represents connected road topology.


### Optional actor gait

`configure(store, mesh, capacity, true)` enables a 16-float transform/custom-data
layout (64 bytes per capacity slot). Use the shared `actor_mesh.gd` asset with
`actor_gait.gdshader`, then call `refresh_animated_positions(delta)` once after
each simulation tick. This accepts finite delta in (0, 0.1]. Horizontal measured
displacement drives facing, phase (four radians per metre), and stride amplitude
(clamped at 2.5 m/s). Vertical grounding does not animate walking; a horizontal
jump over one metre in a tick resets stride. Stopping returns to idle. Selection
refreshes retain gait by generation-checked handle and discard departed handles,
so state remains bounded by render capacity. Gait/facing are presentation state
and reset on readmission/reload; they are not saved entity orientation.

The supplied 72-triangle mannequin uses six rigid parts in one shared mesh, one
material and native per-instance data. Its startup mesh construction is script;
per-instance gait and vertex deformation are C++/shader. No individual animation
nodes or skeletons are created. The main actor adapter enables this path with
256 render slots and retains its existing 16-body simulation cap. A moving row
uploads the full fixed-capacity buffer; unchanged idle rows cause no upload.
This is basic locomotion presentation, not authored character animation,
interpolation, navigation or dense-crowd qualification. See
`docs/evidence/actor_gait` for scoped checks and CPU-call measurements.


### Derived cache ownership

`NativeDerivedCacheIndex` is a Windows, single-worker helper used by the terrain cache adapter. It owns an exclusive root lease, pins the directory, keeps at most 65,536 recognized packet records in native maps/ordered recency, and deletes at most one candidate per `evict_one()` call after identity/size/time revalidation. `acquire`, `track`, `touch`, `forget`, `safe_directory`, `count` and `release` support worker coordination. `evict_one` returns `ok`, `bytes` and `reason` (`evicted`, `empty`, `busy`, `changed`). It is not a general filesystem cleaner or world-save store. Complete byte accounting, admission and idle scheduling belong to `volumetric_terrain/derived_cache.gd`. See `docs/TERRAIN_CACHE_MAINTENANCE.md` for scope and limits.


## Local actor walking routes

`NativeEntityActivation.enable_navigation(admission=Callable())` enables a native,
main-thread incremental local A* planner for `settle`. `actor_world.gd` enables it
by default; the legacy explicit-target `tick` API remains direct motion. Destinations
still live in `NativeActorOrders`. Routes are disposable and recomputed after proxy
reuse; they are not part of the save format.

The planner samples a 0.5 m horizontal grid with support rays, capsule occupancy and
sweeps against terrain/structure layers 1 and 2. It admits conservative walking
edges with quarter-metre intermediate tread samples and <=0.30 m risers (floor
normal Y >=0.85). Capsule clearance is checked around stair corners; native movement
uses a bounded 0.30 m up/forward/landing sweep. Jumping and general multistorey
connectivity remain unsupported. Two support samples per edge
and swept capsule clearance reject obvious gaps and corner cutting. Fine openings
can be missed by the grid. `blocked` means no path in this sampled local graph,
not a proof that every possible continuous/world-scale route is impossible.

Each proxy retains <=2,048 nodes, with a search extent of +/-16 m on each horizontal
axis from its start. All active proxies share twelve work units per `settle` with
round-robin scheduling and a cooperative 750 microsecond deadline. One unit tests
at most one edge (four physics queries for clear flat edges, up to 24 with stair
clearance fallback) or removes up to twelve stale queue entries.
A query/callback and bounded route reset/reconstruction can exceed the deadline;
this is not a hard real-time or total actor-frame guarantee. The priority queue is
bounded by outgoing relaxations (eight per expanded node). Inactive stored actors
have no planner work or extra physics bodies.

`navigation_status(handle)` reports `idle`, `planning`, `following`, `arrived`,
`blocked`, `unavailable`, `search_limit`, or `sleeping`, plus search counts.
Unavailable coverage retries after 0.5 seconds; exhausted/blocked searches remain
stopped until an edit/new order. Stalled movement permits two replans before stopping.
`invalidate_navigation(bounds=AABB())` invalidates intersecting search/route bounds;
an empty box invalidates all proxies. Call it on geometry changes. The demo hooks
terrain publication, structure edits, harvesting and lake changes, supplies dry-ground
admission and displays selected actor status in the HUD. Structure/harvest invalidation
currently covers all active routes. Later actor activation retains the admission callback.

No crowd avoidance, dynamic-obstacle policy, region graph, shared route cache or
large-population qualification is supplied by this local planner. Bodies on the
queried world layers can cause conservative blockage. The next gate is authored
settlement routes and measured planning latency under a declared active population.
See `docs/evidence/actor_local_routes/README.md` and the later
`docs/evidence/actor_cottage_navigation/README.md` for stair/doorway evidence.

Clear destinations first try an incremental straight corridor (<=0.5 m per work
unit) under those same safety checks and limits, then fall back to A* if any segment
fails. Sixteen clear routes and actor-component destination reload have targeted
evidence in `docs/evidence/actor_planning_latency/README.md`; neither qualifies
furnished-settlement navigation or whole-world frame rate.
