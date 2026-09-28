# Building mesh residency and bake reuse

Native block buildings now support bounded nearby rendering and an in-memory LRU bake cache. Travel releases distant meshes and collision without changing saved block cells. Return travel can upload validated cached geometry instead of remeshing. Edits, neighbouring faces and snapshot restoration invalidate dependent cache entries. Nearest-first admission enforces a visual chunk cap and an uploaded attribute/index payload budget; oversized chunks are reported as deferred without a perpetual retry loop.

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

Recorded with Godot 4.7.2 Steam, Zig 0.16.0 and the pinned prebuilt godot-cpp 4.7 SDK. The SDK was reused without recompilation. Graphical evidence uses 1920×1080 exclusive fullscreen, full render scale, Vulkan Forward+ on GTX 1060 Max-Q.

## Evidence and interpretation

- The native suite contains 186 checks covering residency, cache limits/LRU eviction, neighbour invalidation, restore, stale worker completion during travel, nearest mesh admission, fragmented over-budget chunks, nonfinite/invalid configuration, and existing blocks/prefabs/history/static placements.
- After warming four isolated chunks, 100 repeated visits produced 100 cache hits with four total bake jobs and one resident mesh. Authored snapshots remained unchanged. This is a deterministic lifecycle probe, not city-scale endurance evidence.
- Three fragmented chunks exercise byte admission: one mesh retained 2,260,992 payload bytes against a 2,262,016-byte limit; two were explicitly budget-blocked. The retained cache used 8,650,752 capacity bytes against a 16 MiB limit. Raising a too-small mesh budget reused the existing bake.
- Cached reentry publishes at most one nonempty mesh per frame. The travel test waits for an observed live worker before changing focus; fixed frame-count synchronization was unreliable on fast bakes and was replaced.
- All 61 integrated graphical checks passed, including travel away from and back to the twelve-floor block tower. Distant meshes/physics were released; the saved cells were unchanged; return required no additional building bake jobs. Fullscreen construction screenshots were inspected.

Logs, metrics, build hashes and the tower view are retained in [evidence/building_streaming](evidence/building_streaming). Frame intervals in the graphical report are a short warmed stationary sample; they do not establish travel latency, city capacity or performance headroom.

## Remaining scope

Authoritative block data stays resident under the 2,048-chunk cap. There is no disk region streaming, disk mesh cache, distant proxy/HLOD, predictive loading or high-speed collision guarantee. Mesh payload accounting excludes driver/ArrayMesh/physics/material overhead; cache capacity excludes container metadata and worker scratch. A complex upload, collision shape or group of evictions can still cause a frame spike. Static-model collections have their existing spatial batching but do not participate in this block residency policy. Multiplayer, city generation and multi-hour endurance remain tracked in [delivery status](DELIVERY_STATUS.md).
