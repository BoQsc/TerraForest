# Original objective and completion evidence

The original scope remains active. This project must not be called fully game-ready based on the implemented subset below. Each remaining item needs working implementation and evidence at its actual scope, not merely a class, API stub or narrow benchmark.

| Requested outcome | Current state | Evidence still needed for completion |
| --- | --- | --- |
| New combined project; terrain and forest as modular addons | Implemented integration; source folders preserved | Final full-support matrix and release verification after all changes |
| Professional architecture, visuals, resilient long runs and performance headroom | Bounded placement/worker queues, lifecycle tests and short graphical runs; old 120-cycle travel evidence | Multi-hour current-build endurance, measured memory/VRAM/latency tails, matched baselines and visual refinement |
| Volumetric water and lakes | Native static connected occupancy, queries, surface, edit invalidation and compound persistence | Automatic placement, smooth shorelines, underwater/player integration, region exchange or explicitly scoped flow model, bake cache |
| Large caves and mountains | Inherited fixed-size generator | Redesigned native generator, large-world terrain/LOD/collision tests |
| Underground material veins and material variety | Inherited limited material set | Native material registry, seeded vein generation, editing/rendering/persistence tests |
| Volumetric asphalt roads | Pending | Native road volumes, surface/material blending, placement/editing and terrain integration |
| Shape prefabs: cubes/boxels, stairs, spheres, slopes and more | Separate native structures addon: textured cubes, slabs, stairs, slopes and posts; chunk collision, main-world block authoring, native reusable block prefabs, bounded native block undo/redo and compound persistence | Combined block/model prefabs, spheres/curves, material catalog, graphical selection/capture and cross-addon editor commands |
| Large buildings, towns and cities | Native chunked house/tower showcase; bounded nearby block meshes and memory bake reuse; model catalog/placement UI and spatial static-model batching with stable IDs, incremental edits, nearby compound-box collision, native vegetation exclusion, asset-bound snapshots and compound world persistence; 100,000-placement API test | Authoritative region eviction/disk cache, building LOD, prefab selection/capture UI, city generation, model move/scale/history tools, arbitrary concave model collision and dense-settlement rendering tests |
| Efficient world generator/editor with baking and caching | Existing terrain cache; dependency-invalidated native block bake cache and mesh admission budgets; compound snapshot bridge | Unified command/editor model, persistent bake caches, region storage and high-speed loading tests |
| Proper player, toolbelt, inventory, unified interaction | Inherited controller and basic brush HUD | Native movement/interaction/inventory rules, UI, water integration and interaction tests |
| Large multiplayer world, terrain, vegetation, structures and players | Native Windows terrain instances now isolate cancellation; networking remains pending | Multiple-scene cache/save ownership, authoritative region/command model, interest management, bandwidth/backpressure, server + two-client loss/reorder/late-join tests, measured scaling |
| Forest/vegetation including stones, plants and grass | Streamed spruce renderer and bounds | Native scatter/selection hot paths, species tiers, small-object batching and visual/performance tests |
| Efficient world representation and storage | Legacy sparse edited terrain plus native checksummed compound snapshots | Region/delta representation, arbitrary-world addressing, journal/compaction and bounded streaming under travel |
| High entity counts | Native bounded kinematics and bulk transforms | Gameplay simulation, spatial queries, rendering, collision and replication at measured populations |
| Efficient vehicles and high-speed travel | Pending | Vehicle physics, swept collision readiness, predictive streaming, correction and sustained high-speed traversal tests |
| Always 1920×1080 fullscreen for fair graphical testing | Implemented presentation policy and report assertions | Continue enforcing for every new graphical measurement |
| Most systems as Godot addons; no performance-critical GDScript | New entity/archive/water work is C++; legacy streaming/forest schedulers remain GDScript | Native migration and profiling of all remaining hot paths |
| Zig and prebuilt godot-cpp | Implemented, pinned, checksum-verified; debug/release tests | Maintain ABI checks and reproducible release packaging on upgrades |

Relevant evidence: VALIDATION.md (historical terrain/forest), TOOLCHAIN_VALIDATION.md (initial native/fullscreen), WATER_VALIDATION.md (first lake stage), WORLD_STORAGE.md and STORAGE_VALIDATION.md (current compound saves). Historical limitations and timings describe their recorded stage, not the final target.

Offline terrain cache inventory and verified quota cleanup are available via
`tools/maintain_terrain_cache.py`; see TERRAIN_CACHE_MAINTENANCE.md. This does not
replace the pending native runtime cache ownership, eviction and disk-reserve
work. Live-cache cleanup has not been applied while the editor/game are running.
