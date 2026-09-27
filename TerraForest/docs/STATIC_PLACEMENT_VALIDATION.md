# Stable static placement data

The structures addon retains native object IDs and transforms independently of render node identity. Individual same-group moves update GPU slots, larger edits bulk-upload a group, and structural changes rebuild only touched groups. Collections have a stable application-resolved asset key and bounded, checksummed snapshot format.

Validation uses the actual GDExtension built with the pinned Zig/prebuilt godot-cpp SDK:

```text
python tools/validate.py --test static_placements --godot PATH
python tools/test_native_release.py --addon structures --test static_placements --godot PATH
python tools/validate.py --test static_placements --gpu --godot PATH
python tools/validate.py --test structures --godot PATH
```

Results: 45/45 headless checks in debug and release; 49/49 checks on the Forward+ Vulkan renderer, with both display and render target asserted to be 1920×1080 fullscreen; 86/86 existing structures checks including the 100,000-placement regression. Headless Godot uses a dummy renderer that does not retain MultiMesh GPU state, so transform readback checks run only on the real renderer. They verify translation and a rotated, nonuniformly scaled basis after direct slot updates.

Tests exercise signed group boundaries, 64-bit identity, unchanged-batch node preservation, no-op upload avoidance, the direct/bulk threshold, atomic rejection, unknown asset binding, checksum corruption, semantically invalid but correctly checksummed records, restoration, the 4,096-group boundary, singleton migration at capacity, and 1,000 placement/removal cycles without retained group or slot entries. Original logs and library hashes are under `docs/evidence/static_placements`.

These are correctness and bounded-data tests. They do not establish a multiplayer replication protocol, static model collision, multi-hour endurance, city rendering performance, automatic asset resolution, or integration with the compound terrain archive. The showcase still regenerates its static props at startup; its F5/F9 controls currently save only block data. Asset-aware static snapshots are exposed as native API for the next persistence integration.
