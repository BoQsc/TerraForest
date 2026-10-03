# Original objective and completion evidence

## Current delivery priority

Vehicle suspension/contact sampling now runs in NativeVehicleSuspension with
the original spring, damping, travel and force cap. The native pass updates four
rays once per tick; automatic ray updates are disabled and effects/telemetry
reuse those contacts. Five targeted support/force-limit/input checks pass. The
1080p automated drive remains close to the pre-port result (14.7136 m, 49.0202
km/h, four loaded wheels). Both binaries rebuilt; evidence:
`evidence/vehicle_suspension/`. A small script adapter still copies contact data;
motion modes, impacts, effects, fleet activation and streamed-world integration
remain unfinished. No fleet performance claim follows from this single-car test.

The user's own vehicle project is imported under `vehicle_demo`, with their
explicit 0BSD declaration recorded in PROVENANCE.md. NativeDrivingPolicy ports
its steering and longitudinal control rather than substituting the earlier
simple controller. 3,600 original-script comparisons at 60/120 Hz pass with
maximum errors below 1e-6 radians and 1e-5 m/s. A short automated 1920x1080
Forward+ drive at the original 120 Hz physics travelled 14.7 m and reached
49 km/h with four loaded wheels. Both native binaries built; evidence is in
`evidence/vehicle_adoption/`. Launch Vehicle Demo.cmd imports and launches the
isolated comparison scene. Suspension, impacts, damage and accessory runtime
remain scripted; native migration, world collision streaming, vehicle storage,
fleet activation and multiplayer integration remain required work.

Native entity ticks now iterate only a preallocated dense list of nonzero-velocity
entities instead of scanning the entire live population twice. Spawn, velocity
changes, despawn and restore maintain membership; spatial queries and snapshots
still include stationary entities. The 100,000-stationary fixture visits zero
slots per tick; a mixed 100,003 population visits its three movers. Thirteen new
lifecycle/scaling/overflow checks and 54 spatial/storage/identity regressions
pass. Both world-runtime binaries rebuilt. Evidence: `evidence/entity_sleeping/`.
This reduces CPU kinematic work only; physics contacts, AI, animations, entity
paging, rendering cost and multiplayer simulation remain separate requirements.

Road collision now has a targeted capsule traversal check. A native graded cut
through a solid hill is meshed across adjacent 16 m regions; its native face
arrays drive a Godot concave collider and the existing player capsule/movement.
Six checks pass for construction, triangles, uphill traversal, continuous floor
support, grade at the shared edge and downhill return. The uphill sample kept
floor contact for all 140 measured ticks. Evidence: `evidence/road_traversal/`.
This bypasses asynchronous collider publication and does not qualify streaming,
vehicles, road joins or long-run frame performance.

Roads now support an optional native clearance cut (0 disables; maximum 16 m)
in the same density edit as bed construction. The editor exposes it, includes
it in the outline, and protects player/building bounds throughout that height.
The cut follows the graded rounded corridor; material outside the pavement
retains its substrate. Terrain above the cap remains, allowing a tunnel rather
than guaranteeing an open cutting. Both terrain binaries rebuilt. Twenty-four
native checks and fifteen world-editor checks pass; evidence and a 1920x1080
guide capture are in `evidence/road_clearance_cut/`. Terrain undo, vegetation
policy, road-network joins, collision traversal and scale qualification remain.

Road editor aiming now uses the combined native structure/physics ray, rejecting
building hits rather than marking terrain through them. Submission checks the
native block/model overlap mask and rejects unavailable building regions.
The road bounding box plus 0.5 m margin is conservative, particularly on diagonal
routes; this is not exact capsule clearance. Fifteen world checks pass, including
a building inserted before collider publication and removed before acceptance.
Evidence: `evidence/road_structure_clearance/`. This is an editor admission rule,
not a cross-system transaction or multiplayer authority guarantee.

Road selection now has a bounded editor outline showing rounded ends, grade,
width and depth. It rebuilds on selection/dimension changes only, has no
collision or shadows, and hides outside terrain editing or during loading and
inventory use. Green means parameter-valid, not obstacle-free; red indicates
incomplete/invalid selection. Thirteen world checks pass, including aimed
selection, player protection, color changes and no rebuild while unchanged.
The 1920x1080 screenshot in `evidence/road_preview/` isolates the guide at the
selected distant coordinates; it is not evidence of terrain publication there.

The terrain-mode road panel now marks two aimed collision-surface points,
configures half-width/depth and submits the native road command. Release the
mouse with Esc while using a terrain tool to see the panel. Grade/length/world
boundary validation gives feedback; inventory, loading, focus and mode gates
apply; a conservative player-overlap box prevents building around the player.
Selection is temporary; accepted density edits use normal world saving. This
is an initial authoring interface: hill cutting, terrain undo,
network authority and vegetation-clearing policy remain unfinished.

Fixed a rendering regression introduced by asphalt commit `43cf536`: extracting
weight with `fract(UV2.y)` wrapped interpolated LOD integers slightly below their
exact value to nearly full asphalt. Untouched terrain acquired noisy dark pixels
and bands. Decode now subtracts the nearest integer before clamping. The same
1920x1080 Forward+ fixture visibly loses the speckling with only this shader
change; before/after captures are in `evidence/asphalt_weight_fix/`. The earlier
shader-error-free render was insufficient validation and its visible noise was
missed. World data and native binaries are unchanged by this fix.

Native graded road-bed construction is available through
`TerrainWorld.construct_road_bed(a, b, half_width, depth)`. It unions a rounded
road footprint with a graded top into existing terrain density, using asphalt
and the existing worker, meshing and snapshot paths. Both terrain binaries
rebuilt; sixteen short headless checks pass for geometry, input rejection,
idempotence, snapshot restoration, mining, meshing and worker completion.
Asphalt uses saved material ID 4 and continuous native vertex weights; the
shader reuses the existing aggregate texture without overlay geometry. A short
1920x1080 fullscreen Forward+ render passed without shader errors. Its isolated
floating segment validates appearance only, not road placement in a world.
Evidence: `evidence/terrain_road_bed/`. This raises terrain only: hill cutting,
road editor/network tools, surface polish and large-scale performance are
not implemented or certified by these checks. Segments are limited to 128 m,
half-width 0.5–16 m, depth 1–8 m and grade at most 25 percent.

Actual capsule traversal exposed a missing walking behavior: `move_and_slide`
alone stopped at the first quarter-metre stair riser. NativePlayerMovement now
provides a bounded 0.3 m step-up operation, used by the walking controller after
collision-readiness checks; building readiness bounds include raised headroom.
It tests obstacle, overhead clearance, raised travel and landing, with an extra
support ray when the capsule's rounded corner normal obscures a flat tread.
Six physics checks pass for native tower collision, ascent, descent, tall-wall
rejection and low-ceiling rejection; twenty movement-policy regressions pass.
Both player binaries rebuilt. Evidence: `evidence/tower_traversal/`, including
the original first-riser failure. The helper targets the existing upright 0.34 m
radius capsule; arbitrary body shapes/up axes, moving platforms and network
prediction are unqualified. This is not a complete locomotion certification.

Stacked tower-floor alignment is corrected. The original module reaches five
metres in bounds but is designed for a four-metre repeat pitch; using bounds
introduced a landing-height gap. The asset/generator now record explicit
`stack_height=4`, and the library preserves combined pitch in saved assemblies.
Eighteen infill cells were removed because repeated solid stair undersides blocked
headroom below. Six native-geometry checks pass: exact quarter-step heights and
landing continuity, 1.85 m vertical clearance across three flights, persistence
of pitch and invalid-pitch rejection. Evidence: `evidence/tower_connectivity/`.
These are geometric ray checks, not a completed player capsule traversal or
navigation test. Existing placed buildings/personal assets are not rewritten.

The construction editor now exposes **Stack selected prefab**, with a name and
2–32 repeat count. It saves/selects the native assembly through the existing
personal library. Twenty-one library checks and fourteen actual-world checks
pass, including a four-floor assembly, exact library reload and invalid-name
rejection. A separate 1080p panel check verifies layout after widening the
initially clipped count field. Evidence: `evidence/prefab_stack_editor/`.
One full-world attempt missed the 30-second startup deadline before the editor
test; the next completed. Startup variability remains unresolved. Stacking is
authoring, not automatic stair connectivity, roofs or terrain foundations.

Native prefab composition now assembles translated/quarter-turned modules into
one ordinary `NativeBlockPrefab`, preserving material and shape rotation and
rejecting overlaps, invalid inputs and cell/coordinate limits atomically. Seventeen
focused checks pass, including normal world placement, self-source composition,
source immutability and exact resource reload. Sixteen authored tower-floor
modules produced 6,368 cells (one observed composition call: 1.575 ms). This is
synchronous authoring and a flattened asset, not live hierarchical instancing,
terrain grading, connected navigation or settlement generation. No city rendering
performance follows from this test. Evidence: `evidence/prefab_composition/`.

Pickup persistence now has direct disk evidence. The terrain-owned save worker
published authored supplies, fresh provider instances reloaded their identities
and positions, and a second verified save/reopen retained a collected material
in inventory without respawning its supply. An uncollected second material
survived both reloads. A malformed pickup section with a valid outer archive
checksum was rejected before world readiness, with subsequent saving disabled
to protect the original file. The headless test pauses mesh streaming and uses
an isolated temporary save slot; this does not measure live-game save hitches.
Evidence: `evidence/material_pickup_persistence/`; executable coverage:
`tests/material_pickup_persistence.gd`.

The construction palette now authors brick, wood, concrete and metal supplies
through a material selector and **Place supply at aim** action. Placement checks
support normal, building-collision readiness, physical obstruction and existing
supplies. The actual-world test exercises the button and overlap rejection;
the expanded panel is checked after Godot layout and visually at 1920×1080.
These supplies join existing compound-save sections. They remain editor-authored
free placements; block undo/redo does not affect them, and physical settling and
survival costs are unfinished. Evidence: `evidence/material_pickup_editor/`.

Material pickups now connect the entity stores/renderers to the actual world and
player inventory. Four static authored supply types register compound-save
sections; E collects a reachable supply within 2.5 m while walking. Collection
checks terrain/building obstruction, focus, inventory modality and stack capacity.
Inventory shows quantities and cannot equip materials as tools. Eleven addon
lifecycle checks and eight actual-world checks pass, with the 1920×1080 fullscreen
inventory capture inspected. Compound provider tests cover inventory/pickup restore
together; this turn did not repeat on-disk save testing. Evidence:
`evidence/material_pickups/`. The first default-generator world fixture exceeded
its 30-second startup deadline; profile 2 seed 1703 completed the integration test.
That default-profile startup issue remains unqualified. Automated input explicitly
sets the focus state and also verifies unfocused rejection.

Pickups are authored through the addon API, not automatically seeded or produced
by demolition. Editor undo/redo remains separate to avoid loot duplication.
Placement UI, settling, build-cost consumption, region paging and authoritative
multiplayer collection remain missing. Rendering limits are exposed through
`render_status`; dense query overload rejects collection with an explicit notice.

Entities now have store-local persistent identities separate from runtime handles.
Version 2 snapshots retain IDs and their allocation cursor; version 1 still loads
with deterministic migrated identities. Twelve identity checks pass, along with
19 storage and 23 spatial regression checks. Duplicate/cursor-invalid IDs reject
atomically; exhausted IDs cannot wrap; deleted IDs no longer resolve. Evidence:
`evidence/entity_identity/`. This supplies saved-reference resolution, not network
authority or globally unique IDs. Loading an older save rolls back the identity
timeline. Identity-index allocation overhead is outside the pool byte counter.

Native entity positions and velocities now have a versioned storage codec that
registers with the existing compound world-save provider. Nineteen focused checks
pass, including exact 99,999-row round trip, malformed-input atomic rejection,
fresh runtime handles, spatial-index reconstruction, restored motion and archive
corruption detection. Both native binaries rebuilt; evidence is in
`evidence/entity_storage/`. This is provider-level integration, not yet a saved
gameplay population in the demo. Persistent gameplay IDs, archetypes and region
paging are still missing. Whole-population restore stages a second pool and runs
synchronously; it is not a bounded per-frame streaming operation.

Feature delivery remains the priority; laptop thermal feasibility is unproven
and is not a prerequisite for continuing planned functionality. The 60 FPS,
1920×1080 target remains unchanged.

`NativeEntityRenderer` now connects spatial entity queries to a fixed-capacity
MultiMesh in C++. Thirteen focused checks pass, including movement, generation
reuse, invalid queries, dense-region limits and external resource mutation.
A short 1920×1080 fullscreen Vulkan run displayed 49 nearby instances from a
100,000-entity store, visited 256 candidates and uploaded 6,144 bytes at configured
capacity 128. The captured image was inspected. Both native binaries rebuilt
against the existing prebuilt SDK. Evidence: `evidence/entity_renderer/`.
This is a reusable addon adapter, not yet gameplay-world entity integration or
a sustained performance result. It has one shared mesh, translation-only poses,
aggregate culling and explicit truncation rather than nearest-first admission.
Collision, animation, replication and world orchestration remain unfinished.

The native entity store now maintains a 32-unit spatial index and exposes bounded
sphere queries, with explicit incomplete results for candidate/output limits.
Movement across cells, despawn and generation-checked slot reuse update the index.
Twenty-three targeted checks pass, including exhaustive-query comparisons after
movement and negative-coordinate crossings. Local queries inspected four candidates
both at 1,024 and 100,000 entities (one observed call: 19/26 microseconds). Dense
10,000-entity neighborhoods stopped at requested budgets and reported truncation.
The existing 18 runtime checks pass; 240 ticks over 100,000 moving entities measured
3.104 ms median, 4.252 ms p95 and 5.139 ms maximum with index maintenance included.
Evidence: `evidence/entity_spatial/`. These are CPU-only data/kinematics checks.
Gameplay entities, rendering admission, collisions and replication still need
integration; this API is not a completed large-entity game system. Hash-map cells
allocate on demand, and their overhead is not included in the pool byte counter.

Vegetation placement now consults the native water catalog. Each published lake
stores a one-byte-per-horizontal-cell water-column index; bounded batches of up
to 512 roots query at most 16 lakes in C++, without per-root vertical scans.
The optional ecosystem coordinator reconciles only owners intersecting changed
lake bounds and preserves unchanged renderer rows. Removing a lake restores the
original candidate IDs; built terrain and dry/disconnected root locations are
not removed by a blanket rectangular exclusion. Twelve focused native/coordinator
checks pass, along with the existing 45 water and 17 shoreline checks. The real
generated-lake scene also passes four integration checks. Both water binaries
were rebuilt with the prebuilt SDK. Query-index bytes are reported separately
from occupancy and surface bytes. The visual sub-cell shore margin still differs
from conservative occupancy, and population-scale forest/water costs remain
unqualified; this is not proof of complete vegetation support for every biome.

Correction to the repeated **3 FPS construction screenshots** below: direct
instrumentation measured 964–972 ms of synchronous PNG encoding/writing per
screenshot, plus 13–14 ms of GPU readback. The test captured three images during
interaction. Those HUD values were contaminated by test I/O and must not be used
as runtime FPS evidence. A separate 120-frame stationary sample, with streaming
enabled and no capture I/O, averaged 60.0006 FPS (p95 16.748 ms, max 16.797 ms).
The construction test now keeps three image readbacks in memory and defers PNG
encoding until after scene shutdown. All 27 interaction checks still pass; the
repeat sample averaged 60.0026 FPS (p95 16.942 ms, max 17.670 ms). Evidence:
`evidence/construction_observer/before_deferral.json` and `after_deferral.json`.
These roughly two-second stationary samples do not qualify mining/travel,
dense-city rendering or endurance, and do not explain unrelated lake FPS readings.

The construction palette now supports archiving personal prefabs and restoring
the latest archived prefab. Archive moves the original file into a separate
library subdirectory, preserves its bytes and removes it from active selection;
placed blocks are independent and remain intact. Restore works after reopening
the library. Built-in assets cannot be archived, and destination collisions or
I/O failures retain existing files. Eighteen library checks and 27 scene interaction
checks pass, including exact byte restoration and palette synchronization.
The 1080p screenshot was inspected; its 3 FPS HUD reading is not a performance
pass. Archive browsing, renaming and combined block/model prefabs remain open.

Lake rendering now uses a native clipped shoreline built from the density samples
at fill elevation. Connected surface triangles stop at solid contours; fully wet
interiors still merge into rectangles. If sub-cell connectivity reaches the volume
boundary, rendering falls back to the conservative contained surface. Geometry is
built during the worker bake, retained as packed arrays, and copied safely on read;
the 3D density scratch is released. `surface_bytes` reports retained geometry
separately from occupancy bytes. Seventeen shoreline checks, all 45 existing water
checks and 80 generated-basin checks pass. Both native build configurations pass.
The four-check 1080p scene run completed in 9.738 seconds; visual inspection shows
the circular lake's staircase edge removed. Evidence is in
`evidence/generated_lakes/smooth_shoreline/`. The screenshot HUD reads 41 FPS;
this functional check does not establish sustained 60 FPS or rendering-cost parity.
Swimming/containment still uses conservative occupied cells, so the visual contour
can extend into the narrow shore margin reported dry by occupancy queries. Exact
shoreline interaction, varied natural basin shapes and finished water art remain open.

Lake scheduling now admits one outstanding builder reservation instead of
rejecting all lake requests whenever terrain has more than four queued jobs.
Read-only water slices may advance between background terrain owners without
crossing mutation/save/load/unknown barriers. Native sampling retains its 2 ms
yield and admits up to 2,048 points per slice; final flood fill remains bounded
by volume size, not that sampling time budget. Eleven scheduling checks pass,
including real signed Godot instance IDs and reservation retention through poll.
The compound lake persistence/reset test passes again.

The graphical fixture previously let the world overwrite its requested spawn,
then directly moved the camera to unloaded terrain. It now uses normal destination
loading and verifies arrival. The corrected run reached terrain plus nearby lake
readiness in 9.923 seconds, with 49 completed slices, and passed all four checks.
The screenshot shows the basin and water surface together; stepped shores remain.
Evidence: `evidence/generated_lakes/after_scheduling.log`. This is one short
functional observation, not a matched timing comparison against the flawed
fixture or proof of sustained 60 FPS. The earlier all-lakes deadline failure and
remaining water visual/streaming/cache requirements stay recorded below.

Generator 4 adds four deterministic closed lake basins to the mountains/caves/ore
profile. Native command 27 supplies bounded lake definitions; new-world and reset
initialization encode them through the registered water catalog. Normal load uses
the saved catalog, so deleted lakes stay deleted. `Play Lake World.cmd` selects
profile 4 in its own save slot. Profiles 1–3 remain available and unchanged.
Both native configurations build with the pinned prebuilt SDK. Eighty checks over
four seeds verify contained water, generated surfaces and terrain save identity;
11 compound persistence checks cover automatic baking, deletion, reload and reset.
The previous generator compatibility/cave/geology tests also pass.

Rendered validation remains incomplete: one full-scene run completed all four
lakes, a later run completed only two within 50 seconds, and the focused nearby
lake test failed its shorter 25-second readiness deadline. Retained failure:
`evidence/generated_lakes/all_lakes_scene_deadline.log`. Screenshot inspection
confirmed a basin/surface but showed a visibly stepped shoreline and 15 FPS on
that frame. Worker slice scheduling under terrain streaming, smooth shores,
vegetation/water exclusion and persistent water bake caching remain open. These
generated lakes are available for development, not qualified for release. They
use existing static connected occupancy, not dynamic pressure/flow simulation.

`tests/prefab_building.gd` adds a short headless 16-storey authoring check:
78,624 occupied cells in a 64x64x64 selection (the native maximum selection
volume), with floors, windowed walls and stairs. Thirteen checks pass: exact disk
roundtrip, every rotated placed cell, overlap rejection without mutation, full
undo/redo snapshot equality and oversized-selection rejection. One recorded run
took 18.639 ms for native capture, 46.992 ms for capture plus synchronous saving,
5.035 ms to reload, 14.090 ms for placement, 7.285 ms undo and 6.895 ms redo.
The saved asset was 1,258,302 bytes. Evidence is retained in
`evidence/prefab_building/native_authoring.json`. These are individual operation
observations, not latency percentiles. Large capture/save currently exceeds a
16.67 ms frame budget and can hitch. No meshing, collision cooking or rendering
was included; city FPS and large-building authoring responsiveness remain open.

Prefab capture now has a selection-volume outline, distinct corner markers,
`[` / `]` aim shortcuts and a Clear action. Feedback uses three shared-mesh line
instances regardless of selection size; geometry changes only when selection
changes. Oversized bounds are red and labelled before capture. Eleven library
checks and 24 construction interaction checks pass, including actual corner-key
events, exact inclusive bounds, inventory visibility and clearing. Screenshot
inspection confirmed the UI, but its HUD displayed 3 FPS: this functional run is
not performance qualification and does not resolve existing frame stalls. The
cause of that displayed reading was not isolated in this test.

Construction now exposes native block-prefab capture through two aimed corners
and a named save action. The structures addon keeps a shared local library under
`user://building_prefabs`, loading up to 32 assets, and immediately selects captured
prefabs for the existing rotated placement/undo workflow. Capture traverses cells
in C++, refuses unavailable regions and oversized selections, and preserves the
source world. Ten short library checks cover disk reopen, exact records, rotated
placement and invalid selections. The 19-check fullscreen construction test passes
with corner capture and palette selection; its screenshot was inspected. This is
block-only authoring: model-inclusive prefabs, library management and
large-building authoring latency remain unfinished. The
library is separate from world saves, including when capturing from temporary worlds.

Feature delivery takes priority over further speculative thermal optimization.
1920x1080 fullscreen at a 60 FPS target remains the requirement; sustained laptop
thermal feasibility and the deferred mining failure are not declared resolved.

`Play Generated World.cmd` launches generator 3, seed 1703, in the separate
`generated_g3_s1703` save slot. `python tools/run.py --generator 3 --seed 42`
automatically selects another slot; `--slot campaign` explicitly selects a named
save, and existing saves retain their own generator/seed. `--temporary` disables
persistence and `--dry-run` prints the launch command without starting Godot.
The launcher requests 1920x1080 fullscreen and caps at 60 FPS. Focused command
checks cover default/profile/custom slots, zero seed, invalid seeds, path traversal
and raw argument override rejection. These checks do not measure runtime FPS.

Generator audit: current terrain remains a fixed 2000x256x2000 domain. Generator 1
preserves seeded height noise and hard-coded mountain/cave landmarks. Generator 2
adds four seed-derived mountain groups and four connected cave networks represented
by 20 canonical capsules, with tunnels and larger chambers. Select it for new worlds
with `--world-generator=2 --world-seed=2468` after Godot's `--` separator. Existing
saves always determine their own profile; the default remains generator 1. Legacy
base-mesh assets are disabled for profile 2. Twelve native profile checks cover cave
interiors, determinism, cache separation and save restoration; compound persistence
also checks profile/seed survival. Broader biome generation, configurable
world bounds and large-world scaling remain unfinished.

Generator 3 retains profile 2's landscape and adds seeded iron/copper capsules in
32 m geological cells. Native material queries expose stable IDs 8/9 and signed
continuous vein weights; excavation preserves natural material IDs in edited pages.
Rendering blends the weights with exposed rock, while existing placed edit materials
remain separate. Select new worlds with `--world-generator=3`. Nine geology checks
cover discovery, repeatability, mining, save/reload, mesh weights and actual shader
rendering; the full scene test also passes for profile 3. Ore art is preliminary,
mining rewards and a configurable material registry are unfinished, and distant LOD
preservation of thin veins has not been validated. This does not establish large-world
scalability. Profiles 1 and 2 retain their earlier material field.

Terrain saves now write format 2 with explicit generator
ID; format-1 saves are read as generator 1. Unknown generator IDs are rejected
before state replacement. Geometry content keys include generator identity. Future
generator versions must preserve an implementation for old worlds rather than
merely changing this constant. Older application binaries cannot read format-2
saves. Eight focused compatibility checks and compound save/reopen checks pass.

Player tool switching now shares one transition across the toolbelt and legacy
terrain/building/object shortcuts, with active-tool feedback and explicit brush
suppression while inventory is open. `tests/player_hud_smoke.gd` exercises actual
key events for these routes at 1920x1080. Its pending-edit switch check injects
the pending flag; it does not prove concurrent edit completion. This is input
integration, not the completed native interaction/authority system.

`NativePlayerMovement` now computes walking velocity, gravity/jump and flight
displacement for the controller. It rejects nonfinite inputs and timesteps outside
(0, 0.25] seconds. Scene orchestration, collision readiness checks and Godot
`move_and_slide` remain in the controller; the full player redesign is incomplete.
Fourteen native behavior checks pass, including bounded diagonal speed, release,
gravity and invalid inputs. The 1080p scene test also checks flight motion and
stopping. These checks do not establish an FPS improvement, multiplayer prediction,
or exhaustive walking/collision behavior.

Player swimming now uses a chest-depth query against baked lake occupancy and
native bounded swim targets, drag and passive buoyancy. Space ascends; Ctrl dives.
Godot collision and terrain/building readiness still gate movement. Twenty native
movement checks pass, including swimming, and the graphical water integration test
checks submerged ascent and a dry query after leaving the volume. Entry/exit motion,
shoreline traversal, underwater visuals, breathing and networking need further work.
The current lake lookup still scans lake bounds in GDScript; this is not evidence of
scalability to many resident lakes. The water test now keeps 60 FPS/VSync instead of
its earlier uncapped measurement phase.

The water addon now supplies a camera-local underwater environment using ordinary
depth fog. It reuses the environment during steady immersion, restores the previous
camera environment on exit/invalidation/removal, and leaves shared scene resources
unchanged. Seven lifecycle checks and the real-lake graphical test pass; the
underwater screenshot was inspected. This is basic visibility feedback, not finished
underwater art, sound, surface optics or a measured rendering-cost improvement.

Player position, yaw/pitch, flight mode and active tool category now have a 56-byte
native validated `player_pose` section in compound saves. Missing sections retain
default spawn behavior. Restoring a pose goes through destination loading and
collision readiness; capture during loading retains the previous saved pose rather
than saving the temporary staging position. Fifteen codec checks, a disk save/reopen
check and a graphical restore-through-readiness check pass. Individual terrain
brush variants, construction shape/material settings and player attributes are not
yet persisted. This remains a single local player record, not multiplayer identity
or authoritative player-state storage.

The structures addon includes a construction palette for six block shapes, four
materials, quarter-turn rotation and the registered prefabs. It appears in block
mode; Esc releases the mouse for selection. Keyboard selection synchronizes the
palette, and prefabs disable shape/material overrides they do not support. The
1080p smoke test checks selection signals, mode visibility and keyboard sync;
the screenshot was inspected. This adds access to existing native construction
operations; it does not prove large-city throughput or mouse-click placement.

`tests/construction_interaction.gd` now adds a separate ten-check real-scene
interaction test at 1920x1080 fullscreen: native support targeting, palette-selected
wood stairs rotated 90 degrees, injected RMB placement and LMB removal, exact
undo/redo and inventory click isolation. All checks pass and the screenshot was
inspected. Palette selection in this test uses its signals, while placement/removal
use input events. This verifies the small building interaction, not city-scale load.

Individual blocks now share the existing bounded preview renderer: a cell outline
updates at 10 Hz, with player-overlap color driven by the same check as placement.
This outlines the occupied cell, not the detailed selected shape. Inventory and
released mouse hide the preview. The expanded construction interaction test passes
15 checks, including exact preview cell, red overlap and rejection; its preview
screenshot was inspected.

Single-block placement additionally shows a translucent shape preview from the
native building mesher. Its per-world cache is bounded to 24 shape/rotation meshes;
material changes reuse geometry. `tests/structure_preview.gd` verifies all 24
combinations against placed-block vertices/normals/indices, cache reuse and absence
of world edits. The 16-check scene interaction test passes and the stair-preview
screenshot was inspected. No city-scale or rendering-cost claim follows from this.

Resume planned gameplay work: player, toolbelt, inventory and unified interaction,
followed by water/lakes, generator/material veins, roads and settlements. Preserve
the full requirement matrix below. New hot-path rules belong in native addons;
UI and scene wiring may remain in GDScript. Multiplayer authority and persistent
player state remain explicit requirements, not claims implied by a local UI.

**Deferred, not forgotten:** the arrival-frame hitch and sustained laptop power/
thermal qualification remain open. The latest short mining workload produced
maximum visible-change gaps of 137.616/103.745 ms, but a 52.49 ms arrival frame
still failed the overall gate. Evidence: `evidence/mining_flight_failure/cooperative_local_build/`.
This is two three-second holds, not endurance qualification. Reopen immediately
for progressive slowdown, repeated normal-play stalls, incorrect terrain or
vegetation loss; otherwise review before release without blocking all feature work.

The target remains **1920x1080 fullscreen, 60 FPS**. No 30 FPS fallback was added.
Laptop thermal feasibility is unproven. GPU utilization is not a power or thermal
budget; future evaluation must record GPU frame time, watts, temperature and
throttling under matched workloads. Do not pursue iGPU delegation or speculative
GPU optimization as the next milestone.

The entries below describe earlier stages and retain their original limitations.

Repeated edits now preserve unaffected queued terrain jobs and atomically
advance a bounded set of requested fine children. In the corrected 2,176-command
run, original/return median latency is 20.4/20.7 ms. Travel p95 is still 451 ms,
so the foundation remains unqualified. See [refinement progress and observer
correction](TERRAIN_REFINEMENT_PROGRESS.md).

Integrated mining pressure now rejects the foundation at 136, 544 and 2,176
edits. The largest original run reaches 452 ms edit publication;
patch tracing identifies expensive coarse-LOD rebuilds for small edits. See
[measured failures](FOUNDATION_MINING_RESULTS.md) and the
[qualification matrix](FOUNDATION_QUALIFICATION.md). These are open failures,
not an accepted performance baseline.

The original large boundary-frame stall figures are withdrawn as game evidence:
full synchronous benchmark checkpoints caused substantial observer overhead.
The harness now retains only compact progress during capture and writes detailed
traces after capture stops. Original artifacts are preserved with this correction.

Foundation work now replaces column-wide forest clearing after mining with
bounded native surface-support revalidation and preserves unchanged tree renderer
rows. See [localized vegetation support](FOUNDATION_VEGETATION_SUPPORT.md).
This fixes a correctness defect; sustained combined-world performance and
progressively slower mining remain unqualified.

The native mesh cache now uploads bounded batches. A 16-tower / 8-cottage
fullscreen district returned from cache in 0.536 s versus 4.267 s before, with
exactly preserved texture mipmaps and authored data. See
[dense building rendering](DENSE_BUILDING_RENDERING.md). Cold startup spikes,
combined-world city density and endurance remain open.

Dense native paging now covers 4,096 authored chunks across 256 travel arrivals
under a 512-chunk resident budget. It exposed and fixed destination starvation
after pressure eviction; see [pressure regression](REGION_PAGER_PRESSURE.md).
This is cell-storage evidence, not a rendered-city or endurance result.

The persistent main world now uses a native building-region pager for automatic
nearby admission and safe distant eviction. It retains unsaved edits and undo/redo
history, rejects stale read results, and saves partially resident worlds. See
[native region paging](NATIVE_REGION_PAGING.md). City-scale latency and memory,
high-speed readiness and multi-hour endurance remain unverified.

Opt-in metadata-first archive loading now restores region availability without
reconstructing all block cells, and preserves checkpoint identity through later
saves. See [metadata world loading](METADATA_WORLD_LOADING.md). The persistent
main demo now enables metadata loading and bounded automatic region admission.

Fresh block worlds can now initialize checkpoint availability metadata without
loading cell chunks; see [region bootstrap](BLOCK_REGION_BOOTSTRAP.md). Partial
saving and automatic building paging are now connected to the main world.

The main world now publishes block-region checkpoint references through a native
archive adapter, retaining current and backup roots. See [region-backed world saves](REGION_WORLD_ARCHIVE.md).
Legacy full-resident restore limits remain; metadata loading avoids reconstructing
all building cells at startup.

Persistent native catalog checkpoints now preserve referenced block versions through
future edits and collection. See BLOCK_REGION_CHECKPOINTS.md. World-root integration is covered by REGION_WORLD_ARCHIVE.md.

NativeBlockRegionIO now runs disk catalog work on one persistent C++ worker,
bounding queued, active and unread-completion reservations. See BLOCK_REGION_IO.md.
The main pager uses the archive's shared reader instead of opening a second store
owner; see [archive region reads](ARCHIVE_REGION_READS.md).

Authored block regions now support bounded native capture, conditional unload
and reload, availability-aware walking/editing/exclusion, and refusal of legacy
whole-world saves that would omit unloaded data. See BLOCK_REGION_TRANSFERS.md.
A native disk catalog now provides conditional batch publication and explicit
backup recovery; see BLOCK_REGION_CATALOG.md. Automatic block travel paging is
connected; authored static-model region storage remains unfinished.

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
reduces cube/slab bake work while building LOD and authored model-region storage remain open.

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
| Large buildings, towns and cities | Native chunked house/tower showcase; automatic committed block-region paging; bounded nearby block meshes and memory bake reuse; model catalog/placement UI, single-model selection/move/rotate/uniform-scale controls and bounded native model history across assets; spatial static-model batching with bounded nearby paged render buffers, native per-tick upload budgets and page-local transform refresh, stable IDs, incremental edits, nearby compound-box collision, native vegetation exclusion, asset-bound snapshots and compound world persistence; 100,000-placement API test | Authored static-model region storage, persistent derived bake cache, building LOD, prefab selection/capture UI, city generation, model drag handles/numeric transforms/multi-selection, arbitrary concave model collision and dense-settlement rendering tests |
| Efficient world generator/editor with baking and caching | Existing terrain cache; dependency-invalidated native block bake cache and mesh admission budgets; compound snapshot bridge and native block-region paging | Unified command/editor model, persistent bake caches, model-region storage and high-speed loading tests |
| Proper player, toolbelt, inventory, unified interaction | Native fixed-capacity inventory with revision checks and atomic validation; inventory UI and six-slot toolbelt connected to sculpting, blocks and objects; 264-byte loadout persisted in compound world saves with legacy defaults and worker validation; inherited movement controller | Persistent player position/attributes and selected tool, pickup and resource consumption, native movement, unified command routing, water integration and multiplayer authority |
| Large multiplayer world, terrain, vegetation, structures and players | Native Windows terrain instances now isolate cancellation; networking remains pending | Multiple-scene cache/save ownership, authoritative region/command model, interest management, bandwidth/backpressure, server + two-client loss/reorder/late-join tests, measured scaling |
| Forest/vegetation including stones, plants and grass | Streamed spruce renderer and bounds | Native scatter/selection hot paths, species tiers, small-object batching and visual/performance tests |
| Efficient world representation and storage | Legacy sparse edited terrain, native checksummed compound snapshots and exact-version block-region storage/paging | Terrain/model region and delta representation, arbitrary-world addressing, journal/compaction and bounded streaming under travel |
| High entity counts | Native bounded kinematics and bulk transforms | Gameplay simulation, spatial queries, rendering, collision and replication at measured populations |
| Efficient vehicles and high-speed travel | Pending | Vehicle physics, swept collision readiness, predictive streaming, correction and sustained high-speed traversal tests |
| Always 1920Ã—1080 fullscreen for fair graphical testing | Implemented presentation policy and report assertions | Continue enforcing for every new graphical measurement |
| Most systems as Godot addons; no performance-critical GDScript | Native terrain planning, entity/archive/water and structures work implemented; remaining scene and forest schedulers use GDScript | Native migration of remaining scene/forest hot paths, non-Windows planner binaries and profiling across targets |
| Zig and prebuilt godot-cpp | Implemented, pinned, checksum-verified; debug/release tests | Maintain ABI checks and reproducible release packaging on upgrades |

Relevant evidence: VALIDATION.md (historical terrain/forest), TOOLCHAIN_VALIDATION.md (initial native/fullscreen), WATER_VALIDATION.md (first lake stage), WORLD_STORAGE.md and STORAGE_VALIDATION.md (current compound saves). Historical limitations and timings describe their recorded stage, not the final target.

Offline terrain cache inventory and verified quota cleanup are available via
`tools/maintain_terrain_cache.py`; see TERRAIN_CACHE_MAINTENANCE.md. This does not
replace the pending native runtime cache ownership, eviction and disk-reserve
work. Live-cache cleanup has not been applied while the editor/game are running.
