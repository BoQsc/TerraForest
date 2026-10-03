# Volumetric Terrain addon

Copy this folder intact; enable **Volumetric Terrain** in Project Settings → Plugins to expose `TerrainWorld` in Create Node. Runtime use does not need the editor plugin.

```gdscript
const Terrain = preload("res://addons/volumetric_terrain/terrain_world.gd")
var terrain = Terrain.new()

func _ready():
    terrain.save_slot = "campaign_1"
    add_child(terrain)
    terrain.focus = Vector3(800, 70, 1310)
    terrain.initialized.connect(func(message): print(message))
    var error = terrain.start() # Omit material to use the provided textured material.
    if error != OK:
        push_error("Terrain failed: %s" % error)

func _process(_delta):
    terrain.focus = $Player.global_position
```

`start(material = null, temporary_world = false) -> Error` starts the single worker. A new node is required after shutdown. Call `shutdown()` before explicit resource teardown; `_exit_tree()` also joins the worker. A second active world is rejected. Identity global transform is mandatory. The current facade requires `NativeTerrainPlanner`, supplied by the rebuilt Windows x86-64 binaries. The retained legacy Linux binary lacks that class and cannot start this facade until rebuilt with the typed binding and planner. Current validation covers Windows only.

`NativeTerrainPlanner` performs bounded request traversal, hysteresis, priority sorting, coverage fallback and eviction candidate ordering in C++. Runtime GDScript keeps queue submission and scene publication. The facade reports separate `LOD requests`, `LOD coverage` and `LOD eviction` stages as well as the total. See [planner validation and limits](../../docs/TERRAIN_PLANNER_VALIDATION.md).

`sculpt_sphere(center, radius, add = false, material_id = 1) -> bool` submits a sphere edit. `set_block(cell, material_id) -> bool` writes/removes an exact cube. Both return false if not ready, busy, malformed or admission fails. Radius is 0.5–64 m. Material values are 0–3; block material 0 removes. Existing `edit(...)` supports bounded ordered groups of up to four native brush packets, with validation before mutation. Failed native multi-command groups are not rollback-atomic; saving is disabled on that failure path.

`construct_road_bed(a, b, half_width = 3, depth = 2, clearance = 0) -> bool` adds a graded,
rounded asphalt volume through the same worker. Endpoints describe top height;
horizontal length is 1–128 m, half-width 0.5–16 m, depth 1–8 m, grade at most
25 percent. Optional clearance (0–16 m) subtracts the same graded corridor above
the pavement. Zero disables cutting; terrain above the cap remains unchanged.
Packet 28 accepts the legacy 36 bytes or 40 bytes with a trailing clearance float.
Native packet 28
stores density material 4; ordinary brushes retain their existing material API.
Material weights use `UV2.y = integer_lod_step + asphalt_weight * 0.25`;
the integer step is constant within each mesh. This retains the existing mesh
packet layout and gives old cached meshes zero asphalt weight. Older binaries
can read density saves but do not render the new asphalt material correctly.
The demo provides a road panel while a terrain tool is equipped and the mouse
is released (Esc). Aim, release the mouse, mark each endpoint, then build.
Width/depth and endpoint selection live in `road_palette.gd`; density processing
stays native. Selection is temporary, while accepted roads save with terrain.

After a matching terrain publication (or confirmed unchanged result), **Continue
from completed end** starts a new selection at that section's exact endpoint
and restores its width, depth, clearance, surface and shoulder settings. Mark
the next endpoint and build; continuing alone does not edit terrain. Editing
the preview while a section is pending does not change the captured endpoint.
Failed or mismatched results cannot authorize a new continuation, and changing
world epoch clears it. Only the last completed section is retained in memory;
this is not a persistent road network or automatic street-junction planner.
An editor outline shows the rounded footprint and depth, updating only on
selection changes. Green indicates valid parameters, not route clearance; red
indicates an incomplete/invalid selection. It follows normal depth testing.
Terrain undo and network construction are pending.
The demo blocks endpoint selection through buildings and rejects road bounds
overlapping native block/model occupancy or unavailable building regions.
The clearance box includes a 0.5 m margin and may reject nearby diagonal routes
conservatively. Direct native road commands do not enforce this editor policy.

Signals:

- `initialized(message)` — initial/reloaded state is ready for streaming, not proof that all nearby collision has loaded.
- `region_changed(bounds, revision)` — density edit meshes and collision have published. Bounds include reconstruction support. It is suitable for dependent world systems.
- `reload_started` — invalidate dependent transient state immediately.
- `surface_batch_ready(token, points, normals, epoch, revision)` — completion of an admitted query; consumers must check both epoch and revision.
- `message_changed`, `edit_measured`, `stage_measured` — status and profiling.

`request_surface_batch(points, token) -> bool` accepts 1–64 positions, at most eight queued background jobs at admission, and no foreground brush or pending edit. It samples **natural procedural surface support**, not arbitrary edited surface height. A zero normal denotes rejected support. `natural_column_available(point)` rejects out-of-world and edited columns. `request_height()` remains the legacy procedural height API; it is not an edited-surface raycast. Use physics rays against published terrain for arbitrary surface picking.

Save slots use identifier names under `user://worlds/<slot>.trw`, with write verification, backup rotation, and corruption protection. Do not run two processes against the same writable slot: cross-process locking is not supplied. Temporary worlds skip canonical saves. Derived caches under `user://terrain_cache` are disposable and keyed by native binary, codec, style and snapshot.

Inspector tuning: `main_build_budget_us` (2500), `retire_budget_us` (500), `cache_byte_limit` (192 MiB), `cache_entry_limit` (512). These are cooperative CPU/cache targets; an individual GPU allocation or collision creation is not preemptible. Visible roots and requested coverage are protected, so residency can exceed targets when coverage requires it. Native page storage and GPU allocations are additional memory.

Native sources and regression sources are included. `python tools/build_native.py --addon volumetric_terrain --target all` rebuilds the Windows debug/release DLLs with the pinned Zig/prebuilt godot-cpp toolchain. It compiles `core.cpp` and the typed `terrain_binding.cpp`, excluding the historical manual ABI bridge. The old addon-local Windows build command delegates to this tool. Other original targets remain legacy tools; the included Linux binary has not been migrated to the new binding.

The typed Windows `TerrainCore` has instance-owned cancellation and serialized access to each world's mutable state. Commands 12/13 access the owner cancellation counter without waiting for a running mesh operation. Reset/load preserve that counter. `supports_isolated_worlds()`, `build_variant()` and `executing_command()` expose native capabilities and diagnostics; `executing_command()` reports -1 when idle. Allocation-error flags are thread-local in this binding. Keep a strong reference until every caller has finished. The scene facade still admits only one active world pending cache/save ownership changes. This is a native prerequisite for multiple worlds, not a multiplayer implementation.

The save/mesh packet formats and generator are retained. The derived cache fingerprint selects the actual debug/release library. See [terrain native validation](../../docs/TERRAIN_NATIVE_VALIDATION.md) for legacy byte comparisons, concurrent cancellation tests and known limits. Linked godot-cpp uses the accompanying MIT license.

## Graded foundations

construct_graded_bed(a, b, half_width, depth, clearance, material_id = 3)
uses the native graded capsule footprint with a selected edit material (1-4).
Material 4 is asphalt. It shares road bounds: length 1-128 m, half-width
0.5-16 m, fill depth 1-8 m, clearance 0-16 m, maximum grade 25 percent,
and the existing world/bedrock protections. This is a bounded fill-and-cut
operation, not a guarantee that a deep valley becomes supported ground.
It uses worker publication, invalidation and terrain persistence. Command 28
now accepts a 44-byte form with a trailing material uint32; legacy 36/40-byte
forms still default to asphalt. Invalid materials are rejected before mutation.
A narrower road can subsequently pave the foundation without changing grade.
Settlement-wide transactions and editor grading integration remain unfinished.

The main-world Roads / Foundations panel exposes stone grading alongside asphalt.
In terrain mode release the mouse with Esc, choose Stone foundation, mark both
ends and set width, depth and clearance. Grade first; then choose Asphalt road
and a narrower width to pave a street. Equal endpoint heights produce a level
bed. Fill depth and clearance remain bounded; check that the site is supported.
Terrain operations currently have no block-history undo.

Use **Level end to start height** after marking both endpoints to create a
level foundation preview. This changes the selection only; press the build
button to submit grading. The chosen start elevation is retained.
