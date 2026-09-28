# Native building prefab validation

Reusable construction assets now use `NativeBlockPrefab`, a native Godot resource containing canonical occupied-cell records. Placement rotates coordinates and directional shapes, checks all destinations and world capacity, then commits through the existing atomic block edit path. Capturing existing cells creates another saveable resource. Buildings remain editable native chunk data; they do not become thousands of scene nodes or terrain stamps.

Four original assets are included: brick cottage (468 cells), stair flight (46), doorway wall (32), and repeatable tower floor (398). The tower example places twelve floors at four-metre vertical intervals, preserving the staircase opening between floors. It contains 4,776 authored cells. Window openings are intentionally empty; glass, doors and furnishing are not implemented.

## Reproduce

```text
python tools/generate_prefabs.py
python tools/build_native.py --addon structures --target all
python tools/validate.py --test structures --godot PATH
python tools/test_native_release.py --addon structures --test structures --godot PATH
python tools/validate.py --test structure_world --gpu --godot PATH
python tools/test_isolation.py --godot PATH
python tools/export_pack.py --godot PATH
python tools/package.py
python tools/verify_package.py --godot PATH
```

Native builds use Zig 0.16.0 and the pinned prebuilt godot-cpp 4.7 library. No godot-cpp sources were recompiled. Engine verification used Godot 4.7.2 Steam; graphical checks used Vulkan Forward+ on GTX 1060 Max-Q, 1920×1080 exclusive fullscreen with full render scale.

## Recorded results

- **126 native checks passed in debug and release**, including canonical resource records, invalid edit atomicity, all four rotations, matching bounds, snapshot persistence, native resource save/load, capture/reuse, occupied-space rejection, coordinate overflow and world capacity rejection.
- **49 integrated world checks passed**, including actual P/R input selection, placement preview, player exclusion, invalidation of cached validation, complete cottage placement, unchanged terrain density, cottage floor collision, compound restoration, twelve non-overlapping tower floors, upper-floor player collision and stair tread hits through the repeated floor shaft.
- Four independent addon startup checks passed. The structures extension remains usable without terrain or vegetation.

The integrated scene contains 5,557 building cells in **24 mesh chunks and 6,556 triangles**, alongside terrain and 2,398 resident trees at the recorded tower viewpoint. Cell payload is 196,608 bytes; this excludes indices, nodes, meshes, physics, occupancy masks and allocator overhead. It must not be treated as total memory usage.

After a three-second warmup, 240 stationary presentation intervals measured **16.666 ms median, 16.721 ms p95 and 16.785 ms maximum**. This is a short, presentation-paced run. It does not measure isolated GPU time, prove spare rendering capacity, or validate city-scale streaming, multiplayer or endurance. Earlier camera changes incurred transient work, so the warmed sample must not be used as a claim about travel latency.

Original logs, build hashes, reports and inspected fullscreen screenshots are retained in [evidence/prefabs](evidence/prefabs).

## Remaining work

The current editor selects example assets and previews their bounds. Native capture lacks a graphical selection/save workflow. There is no undo, linked-instance editing, automatic terrain grading/foundation extension, combined block/static-model composition, distant building LOD, region eviction, city generator or multiplayer authoring authority. The tower is a structural example with open apertures, not a finished game-ready skyscraper. The full original scope remains tracked in [delivery status](DELIVERY_STATUS.md).
