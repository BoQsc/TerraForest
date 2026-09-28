# Native block construction history

Construction now supports native undo and redo for individual block edits and entire prefab placements. History retains unique cell deltas, not copies of every world chunk. Each demo enables a 16 MiB retained cell-capacity budget and 128 combined undo/redo commands; addon users opt in explicitly. Commands use the same native edit transaction, occupancy updates and asynchronous bake invalidation as forward edits.

No-op and invalid edits preserve redo. A new mutation discards the abandoned future. Byte and command limits evict older history while retaining a valid nearest undo/redo chain. An edit too large for a custom history budget is accepted but clears history as a barrier. Successful world restoration clears history; invalid snapshots preserve it. Optional world-space protection bounds prevent undo/redo from restoring solid cells through the player.

## Reproduce

```text
python tools/build_native.py --addon structures --target all
python tools/validate.py --test structures --godot PATH
python tools/test_native_release.py --addon structures --test structures --godot PATH
python tools/validate.py --test structure_world --gpu --godot PATH
python tools/test_isolation.py --godot PATH
python tools/export_pack.py --godot PATH
python tools/package.py
python tools/verify_package.py --godot PATH
```

Recorded using Godot 4.7.2 Steam, Zig 0.16.0 and the pinned prebuilt godot-cpp 4.7 SDK. The SDK was reused without recompilation. Graphical checks ran at 1920×1080 exclusive fullscreen, full render scale, Vulkan Forward+ on GTX 1060 Max-Q.

## Evidence

- **158 native checks passed in debug and release.** Coverage includes duplicate coalescing, signed chunk boundaries, budget eviction, shrinking a redo chain, oversized-edit barriers, independent prefab history, geometry/collision rebuilding, rejection of in-flight geometry after undo, vegetation occupancy, transformed player protection, rejected loads and reentrant signal listeners.
- The native suite includes **400 deterministic operations checked against an independent state model**, mixing edits, duplicate coordinates, undo, redo, branching and command eviction.
- **57 integrated world checks passed.** Actual Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z input reverses and reapplies edits and complete prefabs. Tests verify vegetation reconciliation, compound save-cache invalidation, player-clearance rejection, timeline reset on load, and the prior building/player/prefab integration.

Reports, logs, build hashes and the inspected fullscreen construction view are retained in [evidence/building_history](evidence/building_history). The broader construction render and collision tests remain part of this regression suite. This change does not establish a city-scale performance result or long-duration memory plateau.

## Scope and remaining work

This is ephemeral scene-thread block authoring history. It is not stored in save files, does not undo terrain/water/static-model operations, and does not supply multiplayer command authority or conflict resolution between players. The memory budget reports retained cell-vector capacity; allocator/deque metadata and transient edit/sort buffers are not included. Region streaming, building LOD, graphical prefab capture, combined command history and the rest of the original objective remain tracked in [delivery status](DELIVERY_STATUS.md).
