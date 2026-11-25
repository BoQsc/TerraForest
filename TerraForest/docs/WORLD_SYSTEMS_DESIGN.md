# World systems expansion — implementation contract

This document records the requested expansion and the intended native boundaries. It is not a list of already implemented features.

Current delivery order, coverage gates and deferred-work triggers are maintained in the [project delivery plan](PROJECT_PLAN.md). Multiplayer implementation is sequenced later; identity, authority, persistence and command-boundary considerations apply throughout. The architectural requirements below remain active.

Implemented paths include the pinned native toolchain, bounded native entity storage/kinematics, fullscreen measurement policy, static volumetric water, seeded cave/mountain/geology generation, terrain road editing, block/prefab construction, a single integrated vehicle, and compound terrain/addon snapshots. Water bakes connected occupancy from terrain density and invalidates after edits. Definitions and stable IDs survive reload; derived occupancy rebakes. See the addon READMEs for API limits, WORLD_STORAGE.md for snapshot limits, and DELIVERY_STATUS.md for evidence. The contract below remains broader than the implementation: it is not a claim of complete settlement generation, fleets, multiplayer or sustained populated-world performance.

## Real-time terrain and water editing

Treat the world editor as the primary workload. A brush at the overview cursor or in first person describes a three-dimensional edit in world coordinates. Independent camera targeting and residency let an author edit remotely while player physics stays at the character. Use held and interrupted strokes, small details and cross-region terrain and water construction to qualify the shared path. A candidate that can change visual quality, editing controls or perceived responsiveness needs a recorded human playtest against the reference before adoption. [Current controls, architecture and acceptance workloads](REAL_TIME_TERRAIN_AND_WATER_EDITING.md#the-world-editor-is-the-primary-workload)

The player should see a pickaxe break, a paid terrain stamp, a bucket transfer,
a shoreline explosion or a strategy brush change the world at the place acted
on. Immediate feedback belongs on the next draw. The entire resident edited
footprint must reach matching terrain, detailed water and real collision in
at most two draws and 33.33 ms at 60 Hz. For mining, record both the time from
button press and the time from the breaking swing's contact. For a barrel,
record ignition, detonation and terrain admission separately. A 64 m cut has
the same deadline across its perimeter as at its centre.

**One operation, one revision.** Local tools, authoring, a dedicated authority
and trusted extensions submit the same versioned commands. Validate identity,
permissions, reach, preconditions, inventory and affected region revisions
before mutation. Stage density and material writes, exact block removals,
water transfers and inventory debits together. A failed or duplicate command
must never spend twice or expose a partial edit. Persist committed state and
its revision. Save, reload and replication can reconstruct derived meshes.
A new subscriber receives a regional baseline followed by ordered changes.

**Resident work.** Keep authoritative samples, cell representatives, bordering
face ownership, collision owners and water connectivity available around active
players. Allow a strategy camera to request detail independently of physics
interest. A brush describes where to search. Committed changed samples describe
what must be reconstructed. Expand that set by the extractor's dependency
halo and include geometry introduced when an authored page first becomes
resident. Reuse unchanged owners. Bound extraction loops, height evaluation
and temporary storage by the dimensions of the repair. Prepare independent
owners concurrently and keep an old owner live until its replacement is ready.
An overlapping edit must validate the previous revision again. Disjoint edits
may run concurrently once their shared dependencies are known.

**Playable publication.** Install render and physics geometry for the affected
owners at a coordinated boundary, retire superseded contact and wake bodies
whose support changed. Joined faces, caves, overhangs, actor sweeps, materials
and normals must agree through handoff. Publish local water picking, immersion
and its detailed surface against that same terrain revision. A lake accounts
for finite volume using regional capacity and outlet connectivity. The sea
accounts for exchange with its boundary. Track disconnected cavities and
changes that open or seal outlets. Wider settling, far-detail generation and
vegetation presentation can finish later. Save ownership and authoritative
support loss must survive a restart at any publication stage.

**Scale and limits.** A world-management request can cover many regions. Show
its bounds immediately and report committed progress by revision. Qualify
the whole resident 64 m edit as one operation. Larger atomic requests need
their own maximum measured footprint and worst-case memory reservation.
Streaming to a new location must report readiness separately. Preserve
player saves on failure. A bounded transaction that prevents an ordinary
lake teleport or new-world generation fails the loading gate.

**Decision and proof.** Start with persistent terrain geometry and standard
engine colliders. The packaged replay demonstrated cheap installation of
already-prepared resources. The unpredicted path must now demonstrate cheap
preparation as well. Record density time, repaired cells, regenerated faces,
bytes copied, shape preparation, physics visibility, post-draw latency and
actual presentation. Compare fresh canonical reconstruction with the local
result, including untouched neighbours. Require two fixed camera angles,
water volume and contact, real body support, zoom reversal, repeated edits,
three cold and three warm routes, and client CPU/GPU p99 at or below 13.3 ms.
The subsequent sections give measured failures, fallback design choices and
the server, modding and multiplayer qualification gates. Current evidence
supports the design direction. Neither dry nor wet editing has passed all
these gates.

### What an edit must carry across the implementation

| Producer | Consumer | Required data and ordering |
|---|---|---|
| Tool or authoring UI | Authority | Operation ID, tool or brush parameters, world identity, expected revisions and required resources. The authority evaluates the live target. Opening an inventory or moving out of reach can invalidate a buffered action. |
| Authority | Local preparation | Committed revision, changed density and material sample runs, removed block IDs, inventory or bucket delta and support changes. Both the optimized large-cut writer and the general brush writer must describe their actual writes. Cache admission for a new page has its own footprint. |
| Local preparation | Render, physics and water | Resolve incident faces and seam dependencies from resident data. Prepare exact replacement geometry, terrain-clipped water, wet-region capacity changes and superseded physics owners. The installation boundary checks that all inputs still refer to the same revision. |
| Playable region | Queries, subsequent edits and peers | Expose the revision, its affected bounds and the first physics step and draw that use it. Gameplay can query the committed region. Distant rendering and wider settling can coalesce work independently. Late joins replay the regional baseline plus subsequent changes. |

Size interactive work by changed samples, incident faces, replaced collision
owners and affected water connectivity. Measure the cost of registering new
physics shapes separately from sampling the density. Capacity, elapsed time
and peak memory for the largest supported operation belong in the same
report. The 64 m case already produces tens of thousands of changed render
records. An implementation that still regenerates all of those records
must demonstrate the required throughput on the reference machine.

## Resident edits and the first playable revision

The current client serializes terrain edits through one pending ticket. The density worker can accept a field change before the visible terrain, registered physics shapes and detailed water are ready. The shared ticket also covers vegetation support and final bookkeeping. A post-commit draw is a different observation from first contact across the footprint. Keep both clocks. On the packaged default 64 m cut, density work took 9.12 ms, the centre appeared at 43.87 ms and the post-commit draw arrived at 127.27 ms. The shoreline traces independently measure the first matching detailed water and collider. [Cut trace](../reports/checks/20261121T083846972823Z/engine.log) and [shoreline traces](../reports/checks/20261121T011517656506Z/normal_gameplay_blast_performance.json).

**Design direction.** Give resident regions an explicit playable revision, separate from the lifetime of a command ticket and from the completion of distant detail. A command declares the terrain samples, collision owners and wet boundaries that can change, including shared borders. Prepare the new local state privately. At publication, rendering, real physics and water queries must agree on that revision. Retain prior state through cancellation or a failed handoff. Vegetation presentation, distant LOD and wider water equilibrium can catch up by revision. Gameplay consequences such as lost support and conserved lake quantity still belong to the authoritative transaction.

The first integration decision is how ordinary physics bodies consume edited terrain before a replacement tile collider is ready. A density ray alone covers targeting. A playable collision implementation must also handle the character capsule, rigid bodies, contacts on either side of a seam and a body already touching the edited area. Make rendering and water consume the same local boundary. Demonstrate this through the packaged game before committing to a particular field-rendering or physics backend. The existing two-angle, frame-two and contact gates remain in force, including edits without preparation time. This is an open implementation decision. The 8 m publication experiment remains opt-in.

## Architecture choices for interactive world edits

**Decision proposed for milestone 5.** Keep the current resident mesh path as the shipping control. Evaluate a bounded local terrain boundary shared by physics, rendering and water first. Commit to that architecture only if the packaged game can replace the old contacts and expose the new boundary within budget. Keep direct density-field collision as the alternative if that integration gate fails. No backend has qualified yet.

### What the current measurements establish

The default cut took 127.27 ms to its post-commit draw in the same package where 8 m triangle pages took 159.94 ms. At draw two none of the nine changed footprint probes matched. The cut generated 45,367 new render triangle records out of 56,610, counting all vertex channels. This measures the opportunity for exact render-record reuse. Collision uses a different representation and needs its own measurement. At sea and lake the floor, physics and detailed water already appeared on the same draw, late. These runs establish a publication delay. They do not establish that whole-lake equilibrium, physics cooking or the GPU individually accounts for that delay. Worker times overlap. [Packaged measurements and cameras](WORLD_FOUNDATION_STATUS.md#changed-triangle-publication-trial)

The current stream uses a single pending edit to gate new edits, some density queries and manual saves. Its worker prepares terrain owners and vegetation support. The stream stages scene and physics resources. The water coordinator has its own occupancy, equilibrium and mesh work, then calls back into terrain for joint publication. Splitting owners leaves these dependencies in place. The valuable existing guarantee is that a player sees the new floor and water together. Preserve it through migration. [Terrain stream](../addons/volumetric_terrain/terrain_stream.gd) · [Terrain worker](../addons/volumetric_terrain/terrain_backend.gd) · [Water coordinator](../addons/volumetric_water/lake_world.gd)

### Implementation choices

| Path | What would change | Advantage | Deciding test or reason to stop |
|---|---|---|---|
| A. Keep triangles authoritative for contact | Generate final terrain directly from dirty density cells into persistent vertex and index storage. Decouple material-only updates from collision. Change the physics adapter so it can replace affected collision geometry with bounded cost. | Best continuity with existing materials, engine bodies and tools. | Demonstrate an actual partial physics replacement on the 64 m cut. Measure new geometry, engine attachment and first visible contact. The shipped concave shape exposes a face array. A GPU buffer edit alone leaves this physics cost unresolved. Reopen this path when a concrete collider integration or a measured bound on full replacement changes the comparison. |
| B. Publish an exact local boundary first **(recommended trial)** | Retain field samples and edit ownership for the resident area. Generate only the boundary needed for play, including unchanged surfaces that cross its perimeter. Use it for a local collider and visible surface. Clip water to that same boundary. Let the detailed mesh take over later. | Preserves standard character and rigid-body behavior if registered colliders can switch within budget. The final high-detail mesh can take longer. | Prove how the old collision is removed **only inside the edit**. A hole cut into the middle of one existing collider cannot be fixed by adding a second collider. Include the cost of replacing any straddling owner and normal residency overhead. Reject if doing this recreates the tile batch, leaves a ghost floor, changes contact, or makes either visible handoff miss its gate. |
| C. Make nearby collision and rendering read the field directly | Add field-based swept contacts and stable contact normals for ordinary engine bodies. Render the edited surface from resident density, with depth, shadows and material handling. Derive wet volume from the same revision. Keep distant meshes for overview. | Removes the requirement to build a triangle collider for each edit. | Most invasive path. Establish that the packaged Windows client and headless authority can run the same body-contact behavior. Test resting bodies, fast motion, caves, overhangs and seams. A pick ray or shader alone proves only one consumer. If this requires a maintained physics backend or engine build, cost its exports, upgrades, Linux portability and mod compatibility before adoption. |

Marching cubes is a surface extractor that could serve A or B. Choosing it does not assign water volume, determine which cavity fills, or publish collision. A spherical field is useful for a droplet fixture. A lake needs a level free surface bounded by connected terrain. Preparing common edits ahead of time can help any path, but the acceptance route includes an unpredicted edit in a resident region. [Concave shape API](https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html) · [Physics server extension API](https://docs.godotengine.org/en/stable/classes/class_physicsserver3dextension.html)

### Full-cut decision from the packaged replay

The current preview cannot represent a full 64 m cut. In `terrain_stream.gd`, `_contact_domain` selects the center plus or minus 8 m and rejects more than four owners. In `core.cpp`, `LocalCut::density` independently limits excavation to that same central prism. The qualification brush has a 32 m radius, changes 36 owners, and has changed probes 24 m from the center. Faster dispatch of that preview cannot make those outer probes pass. Widening the prism would also invalidate its existing seam and cost assumptions.

Keep the engine collider for now. Replaying all 36 already prepared final resources cost 0.59 ms on the recorded control. The nine changed rays matched on the first draw, but the unsupported rigid body remained at rest for seven physics ticks. The production handoff therefore also has to invalidate sleeping support. Preparing fresh engine resources is a separate cost. Prebuilt replay excludes native extraction, resource creation, first installation of uncooked geometry, and water reconstruction.

For the unpredicted edit, the proposed unit of work is the **changed lattice cell and its incident faces**. At authoritative commit, retain the changed density and material sample runs from both the optimized point-cut and general brush paths. Include exact block removals. Map these runs to the cells that consume them and the neighbouring faces and normals that depend on those cells. Keep the canonical vertices, face ownership, collision geometry and material inputs resident across edits. Resolve shared edges against the same revision on both sides. Publish complete affected collision owners whenever the engine cannot patch a collider in place. A full-brush bound remains essential because even exact reuse leaves 45,367 changed final render records on this fixture. Build playable terrain, physics and the local water contact from the same revision. Vegetation sampling, distant lighting, whole-basin settlement and serialization each need their own completion event. None can authorize exposure of a stale floor or a stale detailed water boundary.

The paired control took 155.71 ms from brush input to the final draw. At its observed 12.15 ms from commit to draw, the 33.33 ms budget allows 21.18 ms through commit. The field mutation alone took 11.21 ms, leaving **9.97 ms** for the remaining serial critical path at that draw phase, including admission, preparation and publication. Delivering all 45,367 changed render records afresh within that remainder would require at least **4.55 million records per second** before allowing for collision and water. This is a required rate, not a measured capability. Time overlapping workers by wall-clock dependencies. At sea and lake the corresponding observed publication budgets are 22.98 and 23.93 ms, versus 99.63 and 155.56 ms actually spent from terrain admission through joint publication.

The next feasibility gate for the proposed representation is to generate the **unpredicted** full-footprint replacement from resident data within that budget, starting at the normal input event. Check the nine changed probes, outside support, both camera views and settled-body release alongside the existing independent 3,750-ray comparison. Run the same handoff for the two shoreline blasts. Failing the dry geometry gate rules out promoting this design before investing in a water renderer rewrite. [Paired control](../reports/checks/20261121T091513839473Z/engine.log) · [Shoreline timing](../reports/checks/20261121T011517656506Z/normal_gameplay_blast_performance.json)

### Reworks shared across the choices, in dependency order

| Gate | Owners and work | Evidence required to advance |
|---|---|---|
| 1. Define one edit transaction | Reuse the authority command and archive boundaries. Describe the operation, prior revision, affected density samples, solid structures, bordering owners, water quantity changes and authoritative consequences such as lost support. Separate authoritative commit, local playable revision and final-detail completion in events and traces. | Same cross-boundary command in local play and Windows dedicated mode. Verify duplicate, overlapping and disjoint edits, prior-revision reads, cancellation and save/restart. A failure must leave a recoverable committed revision. |
| 2. Establish real local physics | Drive the candidate from normal mining, authoring and barrel input. Prepare replacement contacts privately. At the physics boundary, replace superseded contacts, preserve unaffected contacts and wake affected bodies. Include old shape retirement in the workload. | Full dry 64 m cut across owners. Exercise the player capsule, a resting rigid body, a moving body, deposition into occupied space and a cave roof. Compare all 3,750 reference rays, grounding, sweeps and actual body motion. Measure the first physics step that observes the edit. This decides B versus C before a renderer rewrite. |
| 3. Publish the visible terrain boundary | Use the accepted local revision for visible geometry, depth and near shadows. Cover the full cut and its perimeter. Carry materials and normals through the transition. Discard superseded jobs by revision. | Two cameras and spaced footprint probes on the actual first two draws. Inspect seams, old surface overlap and holes, before and after final detail arrives. Repeat edits while final detail is outstanding. |
| 4. Bring water into that transaction | Inland water owns a finite quantity and connected basin capacity. Cache regional contributions and outlet connectivity. Sea water has a boundary level and an exchange account. Derive local occupancy, detailed water, picking and immersion from the same terrain and structure revision. Handle opened and sealed outlets, tunnels and isolated pockets. | Both gameplay shoreline blasts, interrupted bucket pour, mining and structure placement/removal. Check conserved lake volume, sea exchange, dry disconnected cavities, contact within 2 cm at shores and 1 cm at the object. Grow the connected lake while keeping the local edit fixed. Track work and memory. If connectivity is ambiguous, measure the fallback explicitly. A global rescan that misses the gate keeps the case open. |
| 5. Rework interest, scheduling and persistence | Reserve nearby field, collision and water data ahead of movement. Give committed local work priority. Bound memory and queue age, coalesce superseded detail, and keep saves and further commands independent of render completion. Persist terrain, water and revisions and regenerate derived resources after load. Handle old saves and interrupted writes. | Load Cedar Vale, create a world, teleport, traverse undisturbed terrain and reverse strategy zoom during edits. Check read-only fixture hash, disk recovery, frame times, memory plateau and the two historical loading-limit failures. |
| 6. Qualify consumers and roll out | Keep binary layouts private. Local gameplay, dedicated authority, replication and trusted mods use versioned commands, queries and post-commit events. Replicate a regional baseline plus ordered edits. Retain the current backend as a selectable control through qualification. | Two real clients converge through reconnect and late join. Then apply the existing 200-player, 64-player hotspot and endurance gates. Measure the small Linux host when available. Promote a backend only after visual, interaction and frame-time gates pass together. |

**Performance contract.** On the existing 1080p reference, keep unpredicted input feedback within the next draw. For local play report input to first matching playable draw and require the full resident edit within two draws and 33.33 ms. For network play separately report admission, transit and receipt to local publication. The 30 Hz authority needs its own tick budget. Preserve p99 client CPU and GPU work of 13.3 ms each, and record individual missed refreshes. Compare three cold and three warm runs with identical saved input, cameras and settings. Run the packaged game on the isolated renderer. Use independent terrain reconstruction, real physics and water queries alongside images. A fixture can eliminate a candidate early, but only normal gameplay can qualify one. [Milestone ledger](PROJECT_PLAN.md)

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

The current finite-cell implementation admits missing regions within a
bounded shoreline excavation up to the highest wet region layer in that
edit. It samples terrain before solving. When an edit creates receivers, the
local snapshot includes resident donor candidates within three horizontal
regions of its seeds. Extra candidates supply water only through the solver's
connected faces. A disconnected pool in the window keeps its previous
quantities. This decision uses simulation state so local play and a headless
authority can make the same selection. Donor cell redistribution still
requires mesh publication across multiple regions; the basin-capacity design
above remains necessary to qualify immediate editing at scale.

The coastal authoring case has a different source of cost. At Cedar Vale's
saved spawn, the 64 m wide box needs a 20 by 20 footprint in the current
four-layer coastal admission band, or 1,600 region keys. The gate accepts at
most 512. Sampling every layer across that rectangle before accepting the
terrain command also delays a single small edit beyond the two-frame target.

For an open sea, the next design to test is a spatial index of cavities
connected to the reservoir at sea level, with explicit stored exceptions for
bucket withdrawals and enclosed water. A terrain transaction should be able to
publish its revision and update affected connectivity and exception records
without materializing every pristine region in the rectangle. Test a wide
coastal cut, a sealed tunnel below sea level, a breached tunnel, deposition
that closes the breach, and a bucket withdrawal spanning save/reload. Check
the resulting volumes and queryable surfaces at several depths. Passing an
unrestricted flat-plane rendering check cannot establish these behaviours.

### Player mining and paid terrain placement (2026-11-21)

The right mouse button enters `world._unhandled_input`, then
`terrain_placement.begin_hold` and `target`. The 3.5 m collision ray supplies
a hit and normal. Native command 39 resolves an exposed sample from 125 lattice
values. The player, vehicle, object, permissions and inventory checks precede
the one-unit debit in `mining_rewards.place`. Command 38 stamps the chosen cell.
An unavailable field takes the ordered worker path and rechecks the slot,
aim, reach and obstructions when the reply arrives. A read of resident pages
uses a try-lock and the same command 39. No field read waits for a page-in
on the scene thread.

The left mouse button starts the authored pickaxe swing in `world_attack.attack`.
At animation contact the game resolves the live target and applies durability.
A breaking terrain hit enters `world_attack.destroy`, the stroke buffer and
`controller._consume_stroke`. The contact-mining brush and paid stamp then
enter `terrain_world.edit`, including water preflight. The stream marks the
revision pending. The ordered worker changes the density, prepares the
resident surface, then emits field and mesh results. The stream stages render
and physics resources and publishes their seam group, including reserved
water owners where needed. A pre-draw drain can install finished hand-edit
work within the remaining staging budget. Save components are captured at
save/shutdown. Pickaxe animation contact and physical ground change have
separate clocks.

On the isolated 1080p game route, the original cold placement took 43.90 ms,
including 17.36 ms to admission. A repeat with resident target lookup took
36.42 ms, including 0.56 ms to admission, 8.24 ms to field notification,
17.51 ms more to installation and 10.11 ms more to the observed draw.
With 10.11 ms to draw and 0.56 ms to admission, the 33.33 ms deadline left
22.66 ms for field and installation together. They took 25.74 ms. Lifting
input priority alone cannot close that gap. A direct terrain-worker rebuild
also missed both deadlines and was removed. Dry mining took 29.10 ms from
contact and 828.90 ms from the start of the swing.

For wet edits the measured workload includes 3,222 replayed resident triangles
for lake mining, 4,806 for a sea barrel and 4,508 for a lake barrel. The first
matching detailed water and collider at the blast probe arrived together on
draw six at the sea and draw ten at the lake. Apply the local physics and
basin-capacity gates above before changing visual quality or enabling a new
renderer. Measure input-to-admission, field notice, installation, physics and
draw separately. Also check real body support, edited area coverage, inventory
accounting and reload.

[Dry route](../reports/checks/20261121T095408497733Z/engine.log) and
[wet route](../reports/checks/20261121T095059227908Z/normal_gameplay_blast_performance.json).
