# Asynchronous geometry and normal packet

The opt-in snapshot worker now captures the positive normal border and generates
both geometry and canonical normals outside the authoritative-world lock. Both
use the shared mesh allocation budget. A normal failure or cancellation discards
geometry too; stale consumption discards both. The locality observer now uses
normal sample bounds, not the narrower geometry bounds.

Godot `experimental_snapshot_poll()` includes `normals`, packed float32 XYZ bytes
parallel to `positions`. Engine allocation failure clears all three arrays.
The theoretical vertex/index limits now allow up to 36 MB of packed data rather
than 24 MB for geometry alone, but the native 32 MiB heap budget can reject work
earlier. Godot copies remain outside that budget. No materials or collision
packet is included, and normal gameplay does not use this path.

Four native surface-worker checks pass: exact geometry/normal parity after source
release, complete allocation release, a positive-border edit that changes normals
alone, and rejection of the entire obsolete surface. Seventeen engine bridge
checks pass, now checking normal count, finiteness, unit length, repeatability
and absence from stale packets. Both extension variants rebuild.

## Loaded result: rejected

The sustained distant-edit probe now counts normal bytes as well. All 640 surface
jobs, 640 changing remote edits and 8,144 density queries complete without
correctness failures. All edits occur with pending work. Transfer totals
338,624,640 bytes across four cases.

One capture call takes **20.351 ms**, exceeding the unchanged 16.667 ms individual
main-call rejection threshold. The test exits nonzero. Query maximum is 4.432 ms,
poll maximum 2.675 ms and completion maximum 75.187 ms. Passing query calls does
not erase the capture failure. This observation does not isolate lock waiting,
OS scheduling or capture execution as its cause; that distinction requires
internal timing before changing scheduling or data representation.

The failed performance result is retained, not rerun until green. These are
short headless CPU tests, not 1920x1080 graphics or endurance qualification.

Commands:

```text
python tools/probe_terrain_snapshot_surface_worker.py
python tools/probe_terrain_snapshot_bridge.py --godot <exe>
python tools/probe_terrain_snapshot_edits.py --godot <exe>
```

Evidence in `evidence/terrain_snapshot_surface_packet/`: `worker.json.gz`,
`bridge.json.gz` and `loaded_rejection.json.gz`.
