# Original objective and completion evidence

Fresh block worlds can now initialize checkpoint availability metadata without
loading cell chunks; see [region bootstrap](BLOCK_REGION_BOOTSTRAP.md). Automatic paging and saving
partially loaded worlds remain unfinished.

The main world now publishes block-region checkpoint references through a native
archive adapter, retaining current and backup roots. See [region-backed world saves](REGION_WORLD_ARCHIVE.md).
Full-resident restore limits remain; automatic runtime paging is unfinished.

Persistent native catalog checkpoints now preserve referenced block versions through
future edits and collection. See BLOCK_REGION_CHECKPOINTS.md. World-root integration is covered by REGION_WORLD_ARCHIVE.md.

NativeBlockRegionIO now runs disk catalog work on one persistent C++ worker,
bounding queued, active and unread-completion reservations. See BLOCK_REGION_IO.md.
The scene residency manager remains unfinished; the world-save root uses native catalog checkpoints.

Authored block regions now support bounded native capture, conditional unload
and reload, availability-aware walking/editing/exclusion, and refusal of legacy
whole-world saves that would omit unloaded data. See BLOCK_REGION_TRANSFERS.md.
A native disk catalog now provides conditional batch publication and explicit
backup recovery; see BLOCK_REGION_CATALOG.md. Automatic travel paging and model-region storage remain
unfinished; the demo does not automatically evict authored regions yet.

Walking now checks native block and static-model collision readiness within conservative capsule
travel bounds before moving, and waits without accumulating motion when an
authored surface is unavailable. See BUILDING_MOVEMENT_READINESS.md and
STATIC_MODEL_READINESS.md. Vehicle paths, multiplayer authority and the native player redesign
remain separate unfinished requirements.

Dense building collision now uses 1,024-triangle pieces, incremental retirement
and explicit readiness instead of the measured ~1.3-second whole-chunk creation
path. See BUILDING_COLLISION_STREAMING.md and the retained baseline in
BUILDING_COLLISION_PROFILE.md. Dense chunks still need many ticks to become
ready; vehicle readiness and physics memory budgets remain open.

Block worlds now reuse one sleeping native bake worker instead of creating a
thread per chunk. Lifecycle, stale-result and shutdown tests are documented in
BLOCK_WORKER_VALIDATION.md; multi-hour endurance remains outstanding.

Native block baking now uses exact shape-dependent scratch grids instead of
quarter-cell expansion for every chunk. Seven legacy mesh fingerprints match,
including cross-chunk partial shapes; see BLOCK_LATTICE_VALIDATION.md. This
reduces cube/slab bake work while building LOD and region storage remain open.

Terrain collision slicing, validation and cache-key preparation now run in a
native worker recipe API. Main-thread shape matching, cooking and node attachment
are measured separately; see TERRAIN_COLLISION_VALIDATION.md. Physics cooking is
still non-preemptible, and long-run/high-speed collision readiness remains open.

Native authored-cell picking supports block editing and model placement without
waiting for block mesh/collision admission. See BLOCK_PICKING_VALIDATION.md.
Player/vehicle collision readiness and model collision residency remain separate
outstanding work.

The original scope remains active. This project must not be called fully game-ready based on the implemented subset below. Each remaining item needs working implementation and evidence at its actual scope, not merely a class, API stub or narrow benchmark.

| Requested outcome | Current state | Evidence still needed for completion |
| --- | --- | --- |
| New combined project; terrain and forest as modular addons | Implemented integration; source folders preserved | Final full-support matrix and release verification after all changes |
| Professional architecture, visuals, resilient long runs and performance headroom | Bounded placement/worker queues, lifecycle tests and short graphical runs; old 120-cycle travel evidence | Multi-hour current-build endurance, measured memory/VRAM/latency tails, matched baselines and visual refinement |
| Volumetric water and lakes | Native static connected occupancy, queries, surface, edit invalidation and compound persistence | Automatic placement, smooth shorelines, underwater/player integration, region exchange or explicitly scoped flow model, bake cache |
| Large caves and mountains | Inherited fixed-size generator | Redesigned native generator, large-world terrain/LOD/collision tests |
| Underground material veins and material variety | Inherited limited material set | Native material registry, seeded vein generation, editing/rendering/persistence tests |
| Volumetric asphalt roads | Pending | Native road volumes, surface/material blending, placement/editing and terrain integration |
| Shape prefabs: cubes/boxels, stairs, spheres, slopes and more | Separate native structures addon: textured cubes, slabs, stairs, slopes, posts and spheres; chunk collision, main-world block authoring, native reusable block prefabs, bounded native block undo/redo and compound persistence | Combined block/model prefabs, additional curved shapes, material catalog, graphical selection/capture and cross-addon editor commands |
| Large buildings, towns and cities | Native chunked house/tower showcase; bounded nearby block meshes and memory bake reuse; model catalog/placement UI, single-model selection/move/rotate/uniform-scale controls and bounded native model history across assets; spatial static-model batching with bounded nearby paged render buffers, native per-tick upload budgets and page-local transform refresh, stable IDs, incremental edits, nearby compound-box collision, native vegetation exclusion, asset-bound snapshots and compound world persistence; 100,000-placement API test | Authoritative region eviction/disk cache, building LOD, prefab selection/capture UI, city generation, model drag handles/numeric transforms/multi-selection, arbitrary concave model collision and dense-settlement rendering tests |
| Efficient world generator/editor with baking and caching | Existing terrain cache; dependency-invalidated native block bake cache and mesh admission budgets; compound snapshot bridge | Unified command/editor model, persistent bake caches, region storage and high-speed loading tests |
| Proper player, toolbelt, inventory, unified interaction | Inherited controller and basic brush HUD | Native movement/interaction/inventory rules, UI, water integration and interaction tests |
| Large multiplayer world, terrain, vegetation, structures and players | Native Windows terrain instances now isolate cancellation; networking remains pending | Multiple-scene cache/save ownership, authoritative region/command model, interest management, bandwidth/backpressure, server + two-client loss/reorder/late-join tests, measured scaling |
| Forest/vegetation including stones, plants and grass | Streamed spruce renderer and bounds | Native scatter/selection hot paths, species tiers, small-object batching and visual/performance tests |
| Efficient world representation and storage | Legacy sparse edited terrain plus native checksummed compound snapshots | Region/delta representation, arbitrary-world addressing, journal/compaction and bounded streaming under travel |
| High entity counts | Native bounded kinematics and bulk transforms | Gameplay simulation, spatial queries, rendering, collision and replication at measured populations |
| Efficient vehicles and high-speed travel | Pending | Vehicle physics, swept collision readiness, predictive streaming, correction and sustained high-speed traversal tests |
| Always 1920×1080 fullscreen for fair graphical testing | Implemented presentation policy and report assertions | Continue enforcing for every new graphical measurement |
| Most systems as Godot addons; no performance-critical GDScript | Native terrain planning, entity/archive/water and structures work implemented; remaining scene and forest schedulers use GDScript | Native migration of remaining scene/forest hot paths, non-Windows planner binaries and profiling across targets |
| Zig and prebuilt godot-cpp | Implemented, pinned, checksum-verified; debug/release tests | Maintain ABI checks and reproducible release packaging on upgrades |

Relevant evidence: VALIDATION.md (historical terrain/forest), TOOLCHAIN_VALIDATION.md (initial native/fullscreen), WATER_VALIDATION.md (first lake stage), WORLD_STORAGE.md and STORAGE_VALIDATION.md (current compound saves). Historical limitations and timings describe their recorded stage, not the final target.

Offline terrain cache inventory and verified quota cleanup are available via
`tools/maintain_terrain_cache.py`; see TERRAIN_CACHE_MAINTENANCE.md. This does not
replace the pending native runtime cache ownership, eviction and disk-reserve
work. Live-cache cleanup has not been applied while the editor/game are running.
