# Native static-model collision

Static placements now have opt-in, nearby box collision proxies. The native collection selects placements by transformed bounds and creates bounded physics-server bodies directly. Stable placement IDs survive ray queries, edits and persistence. Authoring, travel and lifecycle cleanup maintain collision independently of the spatial MultiMesh renderer.

The terrain demo enables this policy for its registered metal-beam model. The integrated test places an independently scaled platform, resolves its placement ID through a real raycast, and lands the existing world player on it.

## Reproduce

```text
python tools/build_native.py --addon structures --target all
python tools/validate.py --test static_placements --godot PATH
python tools/test_native_release.py --addon structures --test static_placements --godot PATH
python tools/validate.py --test structure_world --gpu --godot PATH
python tools/test_isolation.py --godot PATH
python tools/export_pack.py --godot PATH
python tools/package.py
python tools/verify_package.py --godot PATH
```

The Windows native addon uses Zig 0.16.0 and the pinned prebuilt godot-cpp 4.7 SDK without recompiling the SDK. Runtime checks use Godot 4.7.2 Steam. Graphical world checks use 1920×1080 exclusive fullscreen, full render scale, Vulkan Forward+ on GTX 1060 Max-Q.

## Coverage

Recorded results: **82 placement checks passed in both debug and release**, **86 passed with fullscreen GPU readback**, and **65 integrated fullscreen world checks passed**. Addon isolation and resource-path checks also passed.

The placement suite covers configuration validation, bounded per-tick publication, stable 64-bit physics identity, edit/removal/restore invalidation, rejection atomicity, distant eviction, twenty travel visits, large bounds crossing origin groups, count limits, scaled/sheared geometry, transformed collection parents, private physics spaces, in-tree world reassignment, reentry, disable and destruction. A CharacterBody3D lands on a placed model floor. A 100,000-placement collection retains only its configured sixteen nearest bodies and reports the other nearby candidates as deferred; it does not create a physics node per placement.

The integrated fullscreen suite also retains the block building, prefab/history, vegetation reconciliation, persistence and building mesh-travel regression checks. Logs, counters, build hashes and inspected construction imagery are recorded in [evidence/static_collision](evidence/static_collision).

## Limits

This is one authored box proxy per model, transformed into convex vertices; it is not automatic triangle collision or a compound/concave building collider. Pending and budget-deferred objects have no physics. The body and creation caps are per collection, not global memory or time limits. Group-bound updates and selection can still be expensive for dense groups; transformed collections rebuild collision. Proxy creation does not establish high-speed travel safety, city-scale physics performance or multi-hour endurance. Static-model placement UI, vegetation exclusion, compound proxies and the broader objective remain in [delivery status](DELIVERY_STATUS.md).
