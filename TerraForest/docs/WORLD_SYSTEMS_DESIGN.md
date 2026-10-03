# World systems expansion — implementation contract

This document records the requested expansion and the intended native boundaries. It is not a list of already implemented features.

Implemented paths include the pinned native toolchain, bounded native entity storage/kinematics, fullscreen measurement policy, static volumetric water, seeded cave/mountain/geology generation, terrain road editing, block/prefab construction, a single integrated vehicle, and compound terrain/addon snapshots. Water bakes connected occupancy from terrain density and invalidates after edits. Definitions and stable IDs survive reload; derived occupancy rebakes. See the addon READMEs for API limits, WORLD_STORAGE.md for snapshot limits, and DELIVERY_STATUS.md for evidence. The contract below remains broader than the implementation: it is not a claim of complete settlement generation, fleets, multiplayer or sustained populated-world performance.

## Representation and authority

A server-owned world descriptor identifies generator version, seed, material registry, region coordinates, and content hashes. Untouched regions regenerate from that descriptor. Persistent storage records edits, placed prefab instances, water basin changes and entity state; derived meshes, collision, light data and instance buffers remain disposable caches. Windows native terrain cancellation is now instance-owned and tested during concurrent mesh jobs. Multiple authoritative scene worlds still require cache/save ownership changes; the scene facade retains its single-world guard.

Use compact uniform records for homogeneous bricks and dense/palette payloads only for mixed edited bricks. Spatial keys and persistent IDs must be stable and independent of scene node paths. Versioned, bounded binary commands form the common editor/player/network mutation boundary. Server validation controls reach, ownership, materials, inventory cost, rate and revision; clients never directly authorize density edits.

## Addon boundaries and sequence

| Addon/system | Native responsibility | Godot support |
| --- | --- | --- |
| world_runtime | IDs, region ownership, binary command validation, entity storage and native simulation batches | Resource configuration and diagnostics |
| volumetric_terrain | Generator, large cave/mountain field, underground material selection, meshing/collision scheduling | Materials, tooling bindings |
| volumetric_water | Basin volumes, occupancy, displacement queries, active-frontier updates and affected-surface extraction | Water shader, underwater presentation |
| roads | Spline/segment spatial index, asphalt volume stamps and terrain transactions | Editing gizmos and material settings |
| structures | Primitive SDF/boxel definitions, prefab transforms, spatial queries and batch meshing/collision | Prefab catalog/editor and materials |
| settlements | Deterministic lots, road/building placement and region-level baking | Authoring previews |
| vegetation | Native scatter, species batches, selection/culling and streaming; small-object density/LOD tiers | Assets, shaders and authoring controls |
| gameplay | Native character/vehicle movement, interactions, inventory validation and simulation | Toolbelt/inventory presentation and mod hooks |
| replication | Interest management, region snapshots/deltas, sequencing, backpressure and entity interpolation inputs | Connection/session setup |
| world_editor | Same validated commands as gameplay, undo transaction data, bake dependencies | Editor UI and gizmos |

First establish and test the native build, migrate shared hot paths, and define a versioned world format. Then implement terrain/water/materials; road/prefab/settlement generation; streaming/baking; player/UI/vehicles; and authoritative replication tests. A batch of disconnected visual demos would not satisfy the shared storage, editing and multiplayer requirements.

## Water model

Lakes need actual three-dimensional occupancy, floor/terrain intersection and depth queries, not just an unbounded transparent plane. Static connected basins can store fill elevation and bounded occupancy/surface data without updating every voxel every frame. Only edits and active flow frontiers should schedule fluid work. Surface chunks and underwater effects are rendering derivatives. This model supports efficient lakes; fully general high-resolution fluid dynamics is a different performance target and must not be implied by the lake feature.

## Caching and high-speed traversal

Cache keys include generator/material/schema versions, canonical region revision and neighbor dependencies. Bake expensive immutable regions offline. At runtime prioritize collision along a swept player/vehicle travel corridor, then near visuals, then distant detail. Cancel obsolete jobs, cap resident bytes and uploads, and retain safe movement limits when collision is not ready. Teleporting across unloaded space must not bypass readiness gates. Vehicles need swept collision/CCD policy and authoritative correction, not merely faster translation.

## Multiplayer scale and tests

Replication should send region baselines followed by ordered versioned deltas, with per-client interest sets and byte budgets. Players/entities require server ticks, input sequencing, interpolation/reconciliation and bounded queues. Mutable vegetation and buildings use stable IDs; visual grass and small stones regenerate locally from versioned seeds where gameplay allows it. Reliability and scalability require at least server-plus-two-client tests, late join, packet loss/reorder, edits across region boundaries and independent server memory/bandwidth measurements. No player-count claim is justified before those tests.

Graphical measurements are fixed at 1920×1080 fullscreen, 100% 3D scale. Headless correctness and server simulations are reported separately. CPU-only entity integration throughput must not be presented as fully simulated/rendered vehicle or multiplayer throughput.
