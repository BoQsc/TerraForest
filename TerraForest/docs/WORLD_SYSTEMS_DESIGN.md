# World systems expansion — implementation contract

This document records the requested expansion and the intended native boundaries. It is not a list of already implemented features.

Current delivery order, coverage gates and deferred-work triggers are maintained in the [project delivery plan](PROJECT_PLAN.md). Multiplayer implementation is sequenced later; identity, authority, persistence and command-boundary considerations apply throughout. The architectural requirements below remain active.

Implemented paths include the pinned native toolchain, bounded native entity storage/kinematics, fullscreen measurement policy, static volumetric water, seeded cave/mountain/geology generation, terrain road editing, block/prefab construction, a single integrated vehicle, and compound terrain/addon snapshots. Water bakes connected occupancy from terrain density and invalidates after edits. Definitions and stable IDs survive reload; derived occupancy rebakes. See the addon READMEs for API limits, WORLD_STORAGE.md for snapshot limits, and DELIVERY_STATUS.md for evidence. The contract below remains broader than the implementation: it is not a claim of complete settlement generation, fleets, multiplayer or sustained populated-world performance.

## Current priority: one world for dedicated hosting and continuous zoom

Dedicated-server readiness and client frame headroom are current design goals.
The transport rollout can follow in stages. Qualify the same authority and
save data from local play and a separate server process. The installed client
still creates a player, HUD and presentation services in demo/world.gd.
The compound archive includes Windows-specific locking and publication. Both
are concrete dependencies to address when bringing up a portable host.

1. **Extract one complete authority path.** Start with a terrain edit touching
   water at a region boundary. A simulation-only host owns the world descriptor,
   storage lease, edit validation, terrain density and water quantities. Run the
   same command handler from ordinary local play. Keep mesh uploads, camera,
   shaders, audio and menus owned by the client. Dedicated mode needs an explicit
   entry point: a headless launch of the client scene still constructs client
   services. Verify a clean start, acknowledged edit, disconnect, save, process
   restart and reload on a disposable world. Compare affected densities and
   water quantities with the local-game result. Verify archive locking and crash
   recovery separately on each supported server OS.
2. **Give plugins the same commands and queries as gameplay.** Define an operation
   ID, schema version, bounded payload, actor identity from the session, request
   ID and expected revision for mutations. Return accepted, rejected or deferred
   promptly, with an explicit reason or request handle. Publish the committed
   revision and affected regions only after authoritative state changes. Make
   retries idempotent and order conflicting edits. Keep command processing
   independent of rendering, with per-session and world-wide work budgets.
   Provide read-only queries and post-commit subscriptions. Keep stable IDs and
   versioned data at the plugin boundary, with native memory layout private.
   Admit server plugins explicitly and validate content dependencies at join.
   Test duplicate requests, stale revisions, unknown versions and subscriber
   teardown. Start with concrete consumers before standardizing more APIs.
3. **Separate what a camera sees from what a player simulates.** A strategy camera
   subscribes to coarse region summaries and a bounded set of visible detail.
   First-person proximity requests precise terrain, collision, nearby actors and
   water. Keep canonical state independent of camera distance. Share interest
   across overlapping players: simulate a shared region once per tick and fan
   out its committed changes to interested clients. Budget snapshot bytes per
   peer, coalesce superseded visual state and resync a slow peer from a region
   baseline plus later deltas. Preserve ordered gameplay transactions. On the
   client, retain the previous visual until its replacement
   is ready and discard superseded jobs by revision. Gameplay edits invalidate
   just the affected regions and necessary neighbours. Keep immediate local
   feedback separate from an authoritative commit. Compare saved viewpoints and
   continuous zoom captures both ways for holes, silhouette jumps, seams and
   stale collision at edited sea and lake shores.
4. **Qualify replication and headroom before claiming scale.** First exercise a
   dedicated host and two clients over the actual transport, including late join,
   loss, reconnect and simultaneous conflicting edits. Then replay representative
   movement and edits with 32, 100 and 200 concurrent simulated clients, clustered
   and dispersed, with real rendering clients in the busiest region. Measure
   server tick percentiles and worst tick, command-to-commit latency, queue age,
   per-client traffic, snapshot bytes, memory plateau and client frame intervals.
   Pin hardware, resolution, visual settings and server tick rate in each report.
   For the 60 FPS client, count every interval above 16.67 ms and consecutive
   misses, and measure presentation as well as CPU/GPU work. A proposed headroom
   target is p99 CPU and GPU work under 13.3 ms on the reference client, leaving
   about 20 percent of the frame for bursts. Validate idle, sustained traversal,
   zoom and simultaneous edits separately. Select native or packed batch work
   where profiles show repeated CPU, allocation or transfer cost.

The first implemented API is a scene-independent read on NativeGeneratedRegion.
`get_place_position(id)` reads the committed place index and returns Vector3.INF
for an absent ID. `plan_changed(revision)` fires synchronously after successful
publication or snapshot restore, including an empty restore. Validation failures
leave the committed index and revision intact. Subscribe then read current state
when attaching mid-session. The shopkeeper consumes this API. It is a local
post-commit notification on the mutating thread. A network service should
marshal mutations to the authority thread and queue outbound deltas there.

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
## Finite shoreline edits following the November 20 packaged trials

The first-visible crater is the relevant acceptance point. Adding nearby
receivers closed the straight cut. Funding them directly from more donor
cells made many distant mesh owners urgent. Even the reduced window took
434 ms and missed a bank probe. [Measurements and rejected variants](../issues/explosive-combat/water-plan.md)

The proposed next implementation is to cache connected basin capacity by
water elevation. A cached region records connected cavities, the elevations
at which they connect across faces, and how much water fits below a given
elevation. The authority owns one finite quantity per connected basin.
A dig or deposition updates the affected regional capacities and connections.
For a basin whose connections remain intact, obtain the new water level from
its aggregate capacity and conserved quantity. The edited mesh can use that
committed level immediately. Every consumer, including buckets and immersion
queries, must read the same revision. A distant mesh refresh must never
credit or debit water a second time.

Start with an inland excavation against a basin with a known unchanged outlet.
Compare volume, depth, bank contact and shore publication time with the current
solver in the actual game. Then exercise overhangs, breached sills, basin
splits, bucket vacancies, displaced water, ocean exchange and interrupted
save/reload before adopting a new save representation. Store the revision of
the connectivity data with the quantities so a worker cannot commit a result
computed against obsolete terrain. This proposal has no performance result
yet.
