# Block construction and forest exclusion

The terrain scene now uses block occupancy to keep tree volumes out of construction. This is derived from independent building data; it does not carve terrain or save another exclusion mask.

The native kernel maintains 256 16-bit vertical occupancy columns per resident 16-cubed chunk. Edits update that index atomically; loading reconstructs it from validated cells. Transformed tree mesh bounds include the maximum supported wind margin. Partial shapes conservatively reserve their full cell. Vertical overlap is required, so construction below or above a tree does not automatically clear its entire terrain column.

The optional ecosystem coordinator caches at most 36 candidates per resident owner. Current block data filters asynchronous terrain results before publication. A block change queues resident owners once, processing one owner per frame. Removing construction restores eligible cached candidates. Unchanged owners preserve their rendering state; changed owners rebuild their small batch. Eviction/reset releases candidate caches. At the default 169-owner limit, a complete reconciliation can take 169 frames.

## Reproduce

```text
python tools/build_native.py --addon structures --target all
python tools/validate.py --test structures --godot PATH
python tools/test_native_release.py --addon structures --test structures --godot PATH
python tools/validate.py --test structure_world --gpu --godot PATH
python tools/test_isolation.py --godot PATH
python tools/package.py
python tools/verify_package.py --godot PATH
```

Recorded on Godot 4.7.2 Steam with Zig 0.16.0 and the pinned prebuilt godot-cpp 4.7 library. No godot-cpp source was rebuilt.

- 95 native structure checks passed in debug and in a fresh release-only project. New checks cover signed chunk boundaries, face contact, vertical clearance, partial shapes, removal, snapshot reconstruction, translated block worlds, invalid transforms/bounds, huge bounded queries and empty restores.
- 27 main-world integration checks passed with Vulkan Forward+ on GTX 1060 Max-Q at 1920×1080 fullscreen and full render scale. These include tree removal, deterministic restoration, snapshot restore, forest residency reset, exclusion after regeneration, all-resident-tree overlap checks, bounded caches, eviction after failed publication, real block picking and player collision.
- Four independent addon startup checks passed. The structures addon still loads without terrain or vegetation.

Logs, build hashes, test reports and the inspected screenshot are in [evidence/structure_vegetation](evidence/structure_vegetation). Screenshot FPS is an instantaneous display, not an endurance or city-scale performance result.

## Limits

Static-model placements do not yet exclude vegetation. The coordinator and legacy forest scheduler remain GDScript; the spatial occupancy query is C++. Whole-node structure transform changes require explicit coordinator invalidation. Reconciliation is bounded but not immediate across all owners. Building region streaming, LOD, prefab catalogs, city generation, multiplayer and long-duration validation remain pending; see [delivery status](DELIVERY_STATUS.md).
