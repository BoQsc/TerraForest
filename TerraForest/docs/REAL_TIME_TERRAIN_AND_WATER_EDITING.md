# TerraForest real-time terrain and water editing

**Design and qualification record · 21 November 2026 · Milestone 5 open**

A player should be able to break ground, place terrain, empty a bucket or detonate a shoreline barrel and immediately interact with the resulting world. An author should be able to cut across a region boundary and see the whole cut, walk on its new floor and find water wherever the cut opened a connected cavity. The same operation must work from first person, strategy view and the dedicated authority. Water needs depth, a continuous shoreline and consistent volume. Realistic transient flow is outside the requested scope.

**Current verdict.** Small resident edits can meet the deadline in individual runs. The full 64 m cut and both shoreline barrels still miss it. In the packaged cut, none of the nine changed collision probes matched on draw two. At the shores, water eventually occupied the craters, but eventual contact does not establish when they became playable. A separate lake authoring run also exhausted a bounded water transaction. These are two distinct implementation blockers. The design below gives each an owner and a packaged acceptance test.

## Current evidence and decision

| Workload | Observation | Consequence for the design |
|---|---|---|
| Packaged 64 m cut | 131.404 ms from input to first post-commit draw, about 3.94 times the entire two-frame allowance. Zero of nine collision probes matched on draw two. | Remove whole-owner extraction and collider preparation from the resident edit's critical path. Moving finished buffers to another thread cannot recover the required 98.07 ms by itself. |
| Packaged sea and lake barrels | With captures enabled, admission to local draw took 127.124 ms at sea and 314.293 ms at the lake. Both eventually passed 81 crater samples and the sampled 2 cm shore contact checks. | Measure matching draw and collision at the deadline. Run the same path separately with capture disabled for frame pacing. |
| Large finite-water regression | A working-tree candidate passed 35 checks. One donor in an 882-region brush retained 125,000 ml. It sampled 62 additional regions on open terrain and 13 with an obstructing wall. | Starting from wet donors avoids a silent skip at the previous 512-region cutoff. This fixture establishes connectivity and conservation for one donor. |
| Packaged lake authoring attempt | The water worker reported 2,104 regions and exceeded the connected-body transaction limit. The harness also used a water ray longer than the query accepts, so the intended wet starting point was unverified. | Correct the witness and require a confirmed wet target before admitting the edit. Treat the transaction failure as reproducible evidence of excessive work in that run. Keep wet 64 m qualification open. |

[Packaged cut](../reports/checks/20261121T123004783055Z/cut/engine.log) · [Packaged shore timings](../reports/checks/20261121T123004783055Z/shores/normal_gameplay_blast_performance.json) · [Finite donor and wall checks](../reports/checks/20261121T124220985787Z/engine.log) · [Lake transaction failure](../reports/checks/20261121T124339665816Z/lake_cut/engine.log)

**Decision for implementation.** Make the local editable surface a resident resource with stable ownership of its triangles and physics support. Use actual sample writes to identify what to retire and replace. Give detailed water the same solid boundary and maintain connected volume and outlet information as regions change. Install all three products under one revision. Keep the existing reconstruction path as the comparison oracle and for deferred work. Whether exact triangle replacement fits the dense-cut budget remains an engineering question with a defined exit test below.

## What counts as instant

**Current decision.** Keep the production terrain and water paths as the visual and physical reference. Build the next checkpoint around making one committed local field revision available to rendering, collision and water. An earlier isolated checkout run reached the first post-commit draw of the 64 m cut at **138.825 ms from input**, with **zero of nine probes matching on draw two**. The remaining gap is large enough to require changing what the player waits for. The worker upload experiment and the next architectural proof are described at the end of this record.

| Observation | Requirement |
|---|---|
| Local input feedback | Show the accepted tool action or an actionable rejection by the next rendered frame. Record the moment of input, admission, field change, physics visibility, installation and first matching draw. |
| Playable local edit | Within **two draws and 33.33 ms at 60 Hz**, every changed point in the resident footprint must have matching visible terrain, collision and detailed water. Include the perimeter of a 64 m cut. |
| Mining and barrels | Measure mining from button press and separately from breaking contact. Record barrel ignition, detonation and terrain admission separately. Preserve the authored swing and ignition behaviour. |
| Client headroom | At 1080p on the i5-12450H, RTX 4050 Laptop and 16 GiB reference machine, require p99 CPU and GPU work at or below 13.3 ms each. Measure actual presentation at fixed 60 Hz, record consecutive misses and require zero game-attributable missed refreshes on the qualification routes. |
| Remote edits | Record network transit separately. At a 30 Hz authority tick, target p99 tick work at or below 26.7 ms, admission within one tick and resident publication within two rendered frames of receipt. Queues must stay bounded. |
| Larger management operations | Show the requested bounds and readiness immediately. Report progress by committed region revision. Qualify the 64 m operation atomically. Publish the largest tested atomic footprint and its peak memory before promising a deadline for a larger one. |

## Where the current game spends time

**Paid terrain construction.** Right click enters the world input handler and starts terrain placement. A 3.5 m physics ray gives the hit and normal. Native command 39 checks 125 lattice samples and selects an exposed cell. The game checks reach, player and vehicle clearance, objects, permissions, selected inventory slot and available material. It debits one unit and submits command 38. A resident target can be read immediately. A busy worker or unavailable page can still delay admission. When a queued result arrives, the game revalidates the click so a changed aim or slot cannot spend material on the wrong cell.

**Terrain mining.** Left click starts the pickaxe swing. At contact the game resolves the live target and applies durability. A breaking hit enters the stroke buffer, passes water preflight and submits a terrain cut. A swing that does not break the target should not excavate it. The reward must correspond to the material actually removed.

**Publication.** Both operations enter the ordered terrain worker. It commits density, prepares the resident surface and sends geometry to the stream. The main thread prepares render and collision resources. At a wet boundary the terrain and water owners coordinate installation. The first draw showing the complete change is the player-visible result. Save and shutdown capture components at their own boundaries. A field-change notification can arrive substantially earlier than the first playable draw.

[Terrain placement](../addons/player_runtime/terrain_placement.gd) · [Mining and contact](../addons/player_runtime/world_attack.gd) · [Terrain worker](../addons/volumetric_terrain/terrain_backend.gd) · [Publication](../addons/volumetric_terrain/terrain_stream.gd) · [Water](../addons/volumetric_water/lake_world.gd)

## What has been implemented and measured

Commit `31dd1a78` added nonblocking resident target lookup, worker notification for buffered clicks and a pre-draw opportunity to publish finished hand edits. Commit `e7444ea4` bounded the native extractor's height evaluation and temporary density storage by the repair dimensions, including edge samples. For a four-cell cube inside a 16 m owner, this requires **25 height samples and 50 temporary density slots**, down from 324 and 9,252. These counts apply to extraction. They cannot be converted into a whole-game speedup.

The native comparison passed **293 checks**, including fresh-versus-cached mesh bytes, 96 mixed edits, 2,176 replayed edits, world edges, different detail levels and cancellation. First authoring at a page corner invalidated 16 owners on both the previous binary and the candidate. A new page can introduce procedural surface elsewhere within its extraction band, so limiting all invalidation to directly written cells would regress geometry. [Reconstruction evidence](../reports/checks/20261121T103926124660Z/terrain_region_cache.json)

| Actual game route | Observed result | Status |
|---|---|---|
| Dry breaking pickaxe hit | 15.35 ms from impact to matching terrain and collision in the packaged-content run | Passed that run |
| Paid terrain stamp | 22.78 ms in the checkout run. In the packaged-content run it took 50.49 ms and four draws, including 24.51 ms before admission | Intermittent miss |
| 2 m radius authoring brush | First visible geometry at 16.56 ms on draw one | Passed that observation |
| 64 m wide cut | Zero of nine changed probes matched on draw two. First observed geometry at 72.47 ms. First post-commit draw at 139.71 ms | Full-footprint miss |
| Sea barrel | First detailed water and lowered collider matched at 97.39 ms after admission, on draw six. Worst recorded frame in the timing route was 52.83 ms | Late |
| Lake barrel | First detailed water and lowered collider matched at 214.46 ms after admission, on draw thirteen. Worst recorded frame was 78.10 ms | Late |
| Lake mining | Action to local draw took 105.32 ms, including 88.34 ms from admission to terrain publication | Late |

The packaged-content routes used the game scene, an isolated renderer and a read-only Cedar Vale input. The shoreline route recorded the loaded native module. The comparison is diagnostic on a shared machine. It does not qualify the installed Steam launch path, sustained presentation or a universal latency improvement. Both blast craters visibly filled and sampled water reached within 2 cm of the shore. The finite lake preserved its quantity. Angular segments remain visible around parts of the crater outlines. Contact around arbitrary submerged objects remains open.

[Dry checkout](../reports/checks/20261121T103535578960Z/engine.log) · [Dry packaged content](../reports/checks/20261121T103835395617Z/engine.log) · [Full cut](../reports/checks/20261121T104255969895Z/engine.log) · [Shoreline timings](../reports/checks/20261121T104143475472Z/normal_gameplay_blast_performance.json) · [Loaded library](../reports/checks/20261121T104143475472Z/loaded_terrain.json)

| Fixed-camera evidence | First view, before and after | Reverse view, before and after |
|---|---|---|
| 64 m cut | [Before](../reports/checks/20261121T104255969895Z/cut_before_angle_1.png) / [after](../reports/checks/20261121T104255969895Z/cut_after_angle_1.png) | [Before](../reports/checks/20261121T104255969895Z/cut_before_angle_2.png) / [after](../reports/checks/20261121T104255969895Z/cut_after_angle_2.png) |
| Sea barrel | [Before](../reports/checks/20261121T104406426716Z/player_shore_before.png) / [after](../reports/checks/20261121T104406426716Z/player_shore_after.png) | [Before](../reports/checks/20261121T104406426716Z/player_shore_before_reverse.png) / [after](../reports/checks/20261121T104406426716Z/player_shore_after_reverse.png) |
| Lake barrel | [Before](../reports/checks/20261121T104406426716Z/player_lake_before.png) / [after](../reports/checks/20261121T104406426716Z/player_lake_after.png) | [Before](../reports/checks/20261121T104406426716Z/player_lake_before_reverse.png) / [after](../reports/checks/20261121T104406426716Z/player_lake_after_reverse.png) |

## The proposed architecture

### Implementation status at the handoff

Commit `97c49ad0` keeps a revision-checked placement mask within reach. The isolated checkout regression passed 58 checks, including comparison with 81 independently queried target and normal combinations. In the timed checkout run the paid click reached admission in 0.362 ms and matching terrain and collision in 17.425 ms. A breaking pickaxe hit reached the matching result in 18.754 ms from impact. Cold arrival and repeat packaged runs remain open. The earlier packaged observations in the table are retained as the baseline. [Targeting checks](../reports/checks/20261121T105927849161Z/engine.log) · [Timed game run](../reports/checks/20261121T110037078192Z/engine.log)

Commit `0628dd83` records sample runs, first page admissions and exact block writes from both brush paths. The geometry cache uses a complete journal to invalidate affected reconstruction data. The worker carries the footprint to the stream under an edit ticket. In the isolated gameplay checkpoint the 64 m cut reached the first post-commit draw at 142.088 ms. The full cut still needs replacement render and physics geometry, and detailed water still needs to consume the same boundary. [Checkpoint measurements](WORLD_FOUNDATION_STATUS.md#committed-terrain-write-footprint-and-first-consumer-21-november-2026)

A subsequent experiment projected the journal onto 16 m surface owners and reused eligible clean render meshes and colliders. It preserved exact mesh bytes for untouched neighbours in the seam test. On the 64 m cut it retained **zero of 36 tiles**, and zero of nine probes matched on draw two. The experiment is available through `--qualify-surface-owners`. Normal play uses the existing path. The next design comparison must operate **inside** the changed tiles. The surface connector already identifies each crossing by lattice coordinates and axis. A replacement must retire the old triangles at crossings that disappeared, generate the new triangles, handle split faces and include neighbouring normal and material dependencies. Prove equivalence with a fresh mesh and collider before timing the combined install with water. [Full cut trace](../reports/checks/20261121T112051800339Z/engine.log)

### From command to playable world

1. **One authoritative operation.** Local gameplay, strategy tools, dedicated hosting and trusted extensions submit a versioned command with an operation ID, world identity, target, affected revisions and required resources. Validate before mutation. Account for terrain samples, material, block removals, lost support, finite water and inventory exactly once. A rejected, cancelled or duplicate request must leave recoverable state. Subscribers receive post-commit events.
2. **Keep the player's editable area resident.** Maintain authoritative targeting and geometry data across the full reach of an equipped tool, including a new aim direction. Track field revision and ownership independently of the preview marker. A stale or unloaded region must yield a bounded readiness result. Separate simulation interest, collision readiness and camera detail so strategy zoom does not evict the ground under a player.
3. **Pass actual writes to geometry consumers.** Both the general brush and optimized large-cut writer must emit changed density and material sample runs and exact block removals. Expand them to incident cells, faces, normal dependencies, first-page effects and shared edges. Resolve shared edges from the same revision. Retain canonical vertices, material inputs and owner mappings between edits. Measure faces regenerated, collision owners replaced and bytes copied.
4. **Publish a playable region.** Prepare new geometry privately. At the physics and render handoff, remove superseded collision inside the edited footprint, retain unaffected support, wake resting bodies that lost contact and expose the matching visible surface. An old collider that still covers a new hole is a failure even if a targeting ray hits the new floor. Keep the prior complete surface through preparation or cancellation. Validate overlapping edits against the latest revision.
5. **Give adjacent water the same boundary.** Use the committed terrain and structure revision for water occupancy, detailed surface, picking and immersion. A finite lake owns a conserved quantity. Cache regional capacity and outlet connectivity so a local edit can update the affected contribution. A sea exchanges volume with a fixed-level boundary. A sealed cavity below sea level stays dry until a connection opens. Closing an outlet, displacing water with construction and interrupting a bucket operation must preserve the correct accounting. Marching cubes can extract a surface from a field. The field, connectivity and volume accounting determine where water belongs.
6. **Separate subsequent work.** Publish local playability independently of far meshes, vegetation presentation and wider equilibrium. Save and replicate committed terrain, water and revisions. Rebuild derived resources from that state. Keep queues bounded, cancel superseded work by revision and share one active simulation between players interested in the same region. Handle unavailable dependencies and interrupted saves without replacing a player world.

## Why this design and what can disprove it

The measured full cut affected 36 owners. In an earlier paired trial, 45,367 of 56,610 final render triangle records changed. At that run's presentation phase, 11.21 ms for density and 12.15 ms from commit to draw left **9.97 ms** of the 33.33 ms allowance for the other serial work. Regenerating every changed record in that interval would require at least **4.55 million records per second**, before collision and water. These figures set a feasibility target. A centre-only preview cannot satisfy the footprint probes 24 m from the centre.

Reinstalling already-prepared resources for all 36 owners took 0.59 ms in a separate replay. That excludes extracting fresh geometry and preparing new physics resources. The replay also exposed a sleeping body that kept its old support for seven physics ticks. Splitting terrain into 8 m triangle pages increased the measured post-commit draw time from 127.27 to 159.94 ms in another paired run. Those results favour measuring the generation and retirement of an exact local replacement before adopting smaller pages globally.

**First choice:** retain ordinary engine colliders and render the exact local boundary from resident data, including the perimeter. Measure the full cost of replacing every collision owner crossed by that boundary. If this cannot meet the gate, evaluate direct density-field contacts and rendering against identical sweeps, rigid bodies, materials, shadows, seams and timings. Adopting a custom physics backend also requires a maintainable dedicated-server and export path. [Architecture alternatives and paired measurements](WORLD_SYSTEMS_DESIGN.md#architecture-choices-for-interactive-world-edits)

## Implementation order and exit tests

The opt-in triangle-page implementation can now read an arbitrary mask of
8 m sections directly from the accepted terrain revision. It preserves exact
mesh attributes and collider faces in the seam regression. The large authoring
cut selected all 144 sections in 36 tiles. In the measured run, writes and
their dependency halos accounted for 132 sections and pre-existing dirty state
accounted for the other 12. Generating all selected sections separately
took 291.587 ms from input to the first post-commit draw. Dense tiles now use
the shared indexed mesh path. Even with that fallback the result took
191.452 ms. Keep this mode experimental. For dense edits the next design
must change the cost of generating and installing a changed surface. Finer
spatial partitions alone leave nearly the entire operation on the critical
path. [Cut and selection measurements](../reports/checks/20261121T113759829414Z/engine.log)

| Order | Deliverable | Evidence required to advance |
|---|---|---|
| 1 | Resident authoritative placement targeting | Unpredicted cold click, moving aim, rapid stacking, slot change, obstruction, cancellation and exactly one debit. Record admission and first matching draw separately. |
| 2 | Actual changed-sample output from both terrain writers | Compare changed records against a fresh field, including material-only edits, exact blocks, new pages, shared edges and unchanged neighbours. Verify failed and repeated operations across save/reload. |
| 3 | Local real physics and render installation | Use the full 64 m cut, all nine footprint probes, the independent 3,750-ray comparison, player capsule, resting and moving bodies, cave roof and deposition into occupied space. Check both camera views at draw two and after final detail. |
| 4 | Detailed wet publication in the same revision | Fire ordinary gameplay barrels at both shores. Mine and deposit, scoop and pour, interrupt a bucket transfer, open and seal a cavity and intersect a submerged object. Require conserved lake volume, recorded sea exchange, shoreline contact within 2 cm and object contact within 1 cm. Increase lake size with the local edit fixed. |
| 5 | World management, persistence and travel | Create a world through the normal UI, reopen existing saves, teleport to both shores, travel and reverse zoom during edits. Exercise the historical equilibrium-memory and connected-body transaction failures. Verify atomic save ownership, crash recovery, memory plateau and bounded queue age. |
| 6 | Release qualification | Pin build, save hash, hardware, driver, visual settings, resolution and cameras. Run three cold and three warm routes through forest, trader, shores, underground and travel. Retain frame distributions, worst frames, actual missed refreshes, matched images and continuous zoom video. Keep saved inputs read-only and test outputs receipt-owned. |

## Dedicated authority, multiplayer and extensions

Local and dedicated gameplay must use the same edit handler. The first authority proof is a cross-region terrain cut affecting water, followed by save, termination, restart and comparison of samples, quantities and revisions with local play. A Windows dedicated host runs simulation without cameras, HUD, audio or GPU resources. Late joiners receive a region baseline plus ordered changes. Test stale messages, duplicate commands, loss, slow receivers and reconnects with two real packaged clients.

Forge remains the default discovery path. Qualify gameplay authentication, replication and transport under load separately. Trusted extensions need versioned commands, bounded queries, post-commit subscriptions, declared dependencies, persistence and listener teardown. Unknown save sections must survive a missing mod.

The Windows release target is 200 active players with a 64-player hotspot, measured at 32, 100 and 200 players using separate load generators, three repeat runs and an eight-hour soak. Report bytes per region and peer, bandwidth, tick work, oldest queue item and recovery peaks. The one-core, 400 MB total Linux host has a separate measured capacity gate. That host is currently unavailable. [Milestone ledger](PROJECT_PLAN.md) · [Current foundation status](WORLD_FOUNDATION_STATUS.md)

## Native execution, storage and qualification decisions

Keep density, material, occupancy and region revisions authoritative on the CPU so the same command runs on a GPU-free host. Use packed native buffers in the loops that visit samples, generate faces and prepare collider input. Keep GDScript responsible for input, scheduling and engine resource ownership. A compute shader is a candidate for client surface extraction if a measured CPU stage exceeds its budget. Time dispatch, synchronization, upload and first matching presentation together. A faster GPU surface only helps the joint deadline when physical contact and water reach the same revision in time.

Persist authored state and finite water quantities at a common recoverable revision. Include an operation identity for retry and a schema version for migration. Prepare changed region data before atomically publishing its save index. On interruption, reopen the most recent complete revision and verify unaffected neighbours and inventory. Derived triangles, placement masks and render resources can be rebuilt. Measure bytes written by a single edit and peak memory during save, reload and teleport. The reported “Water equilibrium snapshot exceeds memory budget” and “Connected water body exceeds bounded transaction” errors each require a regression using the previously failing world and travel path.

Run the next packaged checkpoint when changed writes drive actual render triangles, physics and adjacent detailed water. Exercise a paid placement, a breaking mining hit, the entire cut and both gameplay barrels. Use fixed cameras and record the presented revision at every sampled point through draw two. Pair shoreline images with collision and wet/dry probes on both sides of the boundary and around the submerged object. Repeat after a bucket interruption and during an overlapping edit. Record wall time and draw count together so a stalled frame cannot satisfy the gate. Run through an isolated renderer on a read-only save input, independently of the player's desktop and Steam shortcuts.

If the deadline is missed, attribute the first late revision to admission, field mutation, triangle generation, collider preparation, water preparation, main-thread installation or presentation. Compare the measured cost with the remaining serial budget before changing the design. The current priority is the first complete playable publication for an unpredicted large or wet edit. Cold construction before residency remains a separate regression gate.

## Worker upload experiment and next architecture decision

The 21 November working-tree candidate reused resident physics bodies as the number of collider shapes changed and prepared terrain upload buffers on a native worker. The opt-in upload path reproduced the engine's mesh bytes with both index widths. The isolated field suite passed 226 checks, including adding support, removing it and restoring it on rollback. These results establish correctness for those operations. The following timings came from the checkout game with worker packing enabled. Subsequent packaged measurements are recorded in the current evidence table above. [Field and collider checks](../reports/checks/20261121T115657538235Z/engine.log)

| Operation | Measured interval | Result |
|---|---|---|
| Full 64 m cut | Input to commit 127.666 ms, then 11.159 ms to the first post-commit draw | 138.825 ms total, 105.495 ms over the 33.33 ms deadline. Forty packed surfaces installed. |
| Sea barrel | Admission to terrain publication 88.089 ms, then 11.663 ms to the local draw | 99.752 ms combined. Worst frame 49.422 ms. |
| Lake barrel | Admission to terrain publication 188.210 ms, then 8.326 ms to the local draw | 196.536 ms combined. Worst frame 76.003 ms. |
| Lake mining | Admission to terrain publication 88.220 ms, then 13.908 ms to the local draw | Input to local draw 102.262 ms. Worst frame 30.298 ms. |

The barrel intervals begin after terrain admission and exclude ignition. The local draw measurement alone cannot certify that the detailed water boundary matched everywhere. For the full cut, even eliminating the entire measured commit-to-draw interval would leave 127.666 ms on the critical path. In a separate replay using prepared resources, all nine rays changed and the perimeter held, but on draw two the physics server reported downward velocity while the scene body still reported sleeping. Its motion became visible on draw three. Keep that discrepancy as an explicit contact regression. [Cut and rigid-body observations](../reports/checks/20261121T115303447428Z/engine.log) · [Shoreline and mining timings](../reports/checks/20261121T115510016373Z/normal_gameplay_blast_performance.json)

### Next implementation checkpoint

1. On admission, have the authority produce a revision containing the exact density, material and local water changes, the required boundary samples, and the revisions it replaces. Bound the synchronous work by the resident edited footprint. Keep a finite lake's conserved quantity and any sea exchange explicit. Test the same cut against progressively larger connected lakes.
2. Give local rendering and physics access to that revision before background mesh reconstruction. For rendering, evaluate the changed field inside the affected bounds and suppress the superseded surface there, including in depth and shadow passes. For physics, exercise ordinary character sweeps and rigid-body support against the same boundary. A ray-query override alone cannot satisfy this requirement. Keep ordinary engine colliders wherever their measured preparation fits. Require a CPU-only path on the authority.
3. Publish terrain, detailed water and contact using the same revision. Retain each prior resource until its replacement is ready. Discard a late background result if a newer edit superseded it. Validate the transition at seams and inside the cut when mining, deposition and bucket commands overlap. Save and replicate the committed state through the shared command path.
4. At the first integrated checkpoint, use the packaged game with the full cut and both shoreline blasts. Sample all nine cut positions and the perimeter, record physics-server and scene-body state, and capture two fixed views at draw two and after settling. Repeat the known lake bucket interruption and submerged-object case. Accept the redesign only when geometry, physical contact, water, frame times and image quality pass together. Keep the experimental switches disabled by default until then.

## Joint edit ownership and failure handling

| Stage | Work on the resident edit path | Completion witness |
|---|---|---|
| Admit | Resolve the tool contact, permissions, inventory, resident pages and expected revisions. Reserve the edit footprint and resources. Give a repeated command its original outcome. | One operation ID, input and admission timestamps, accepted bounds and starting revisions. |
| Prepare | Stage density and material writes. Find incident cells, shared edges and normals. Retire vanished triangles as well as adding new ones. Reuse unaffected geometry. Prepare matching physics support and detailed water against this staged boundary. | Compare exact geometry, contact and occupancy with fresh reconstruction. Record changed faces, bytes, solver visits, CPU work and queue age. |
| Commit and expose | Validate dependency revisions again. Apply resource debits, rewards and finite-water transfers once. Hand off the complete local result at the physics/render boundary. Wake bodies whose support disappeared. | First presented draw with matching terrain, collider and water across the footprint. Verify that a character and a resting body experience the new support. |
| Reconcile | Let wider water equilibrium, distant detail, save and replication consume committed revisions. Discard obsolete worker output. Retain recoverable state through an interrupted save or rejected edit. | Replay, restart, overlap and late-join checks reproduce the committed quantities and revisions, with bounded queues. |

For water, maintain a per-region summary of open capacity by elevation and the outlets that connect open space to neighbouring regions. A terrain edit invalidates the intersected summaries and the faces it opens or closes. Query cached basin capacity to allocate a finite transfer and account explicitly for any exchange with the sea. Stage the local water boundary together with the terrain. A split basin, newly connected cave or submerged structure can change which volume is reachable even when its elevation is unchanged. Compare each case against the full solver before accepting the summary method. Measure work as the surrounding lake grows with brush size held fixed. This is a proposed implementation and still needs a measured worst case.

For authoring and management, distinguish a resident atomic command from a selection spanning unloaded regions. The 64 m command must meet the full-footprint deadline. For larger selections, report readiness, the atomic unit, the committed bounds and any remaining work to the caller. Persist progress so retrying or cancelling cannot duplicate material or water. Measure the largest atomic footprint that fits the deadline before advertising it in tools or the mod API.

## Order of proof

1. Start with the player's ordinary construction click and breaking mining hit. Trace input, target validation, inventory, actual writes, changed triangles, physics support, water and first matching draw under one operation ID. Include an unpredicted click and a boundary hit.
2. Apply that same path to the entire 64 m brush. Compare the reconstructed result at every changed cell against the reference. Verify all nine gameplay probes, the perimeter and rigid-body support at draw two. Reject a candidate that improves average hand edits while still waiting for the wide mesh batch.
3. Exercise sea and lake barrels, a confirmed wet 64 m cut, interrupted buckets, submerged-object contact and rapid overlapping operations. Record volumes, sea exchange, collision, two matched views and first playable draw. Reopen and teleport into the failing saved world to check both historical loading errors.
4. Run the pinned packaged routes with separate timing and capture passes. Record client presentation, CPU, GPU, memory, save peaks and queue age. Keep the milestone open for any late revision, unexplained recurring miss, visual gap or lost quantity. Apply the broader host, multiplayer and extension gates in the project ledger after the local edit contract passes.

[World architecture](WORLD_SYSTEMS_DESIGN.md) · [Project milestones](PROJECT_PLAN.md) · [Implementation and measured failures](WORLD_FOUNDATION_STATUS.md)
