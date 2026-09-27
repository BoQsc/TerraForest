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

`start(material = null, temporary_world = false) -> Error` starts the single worker. A new node is required after shutdown. Call `shutdown()` before explicit resource teardown; `_exit_tree()` also joins the worker. A second active world is rejected. Identity global transform is mandatory. Supported native binaries are Windows x86-64 and Linux x86-64; this revision was exercised on Windows only.

`sculpt_sphere(center, radius, add = false, material_id = 1) -> bool` submits a sphere edit. `set_block(cell, material_id) -> bool` writes/removes an exact cube. Both return false if not ready, busy, malformed or admission fails. Radius is 0.5–64 m. Material values are 0–3; block material 0 removes. Existing `edit(...)` supports bounded ordered groups of up to four native brush packets, with validation before mutation. Failed native multi-command groups are not rollback-atomic; saving is disabled on that failure path.

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
