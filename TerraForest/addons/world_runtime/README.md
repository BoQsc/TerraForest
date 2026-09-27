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

`step(seconds)` accepts finite durations in (0, 0.1]. It integrates constant velocity without allocating per entity. This is **kinematics**, not a collision/physics/vehicle solver. Nonfinite inputs and overflow-producing ticks are rejected before mutation. Handles do not alias recycled slots or reconfigured pools; after the positive generation namespace is exhausted, spawning fails instead of wrapping.

`multimesh_transforms()` produces one 12-float-per-instance buffer in dense live order. It does not submit GPU work. Use that output with a 3D MultiMesh configured without color/custom data. Dense order can change after removals; it is not a persistent entity ID. `statistics()` reports capacity, live count, ticks and reserved pool bytes.

All access is owned by one simulation thread. This class is not concurrently mutable and its handles are local to its instance. Rendering resources and scene nodes still belong to Godot's main thread. Multiplayer authority, network IDs/replication, collision, AI and vehicle systems are future integrations, not implied capabilities of this pool.

Build from the repository using `python tools/build_native.py --target all`. The full build contract and upgrade policy are in `docs/NATIVE_DEVELOPMENT.md`. Keep the bundled godot-cpp MIT notice when redistributing linked binaries.
