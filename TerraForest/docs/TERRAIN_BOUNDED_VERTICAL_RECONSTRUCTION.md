# Bounded vertical reconstruction

The native candidate mesher, sequential world sampler and surface builder now
accept a half-open cell interval `[y_begin, y_end)`. Boundary samples include
`y_end`; global edge IDs and interpolation order remain unchanged. Existing calls
default to the original full-height range. The sampler starts directly at the
requested height rather than scanning and discarding preceding layers.

Geometry and normal dependency checks accept the same interval. Normal
dependencies include the positive one-sample halo in Y as well as X/Z. Surface
metadata retains the interval. Invalid ranges fail before sampling; cancellation
still discards partial output. This does not change the public Godot packet format.

## Initial direct reconstruction evidence (645ad96)

`python tools/probe_terrain_bricks.py` passes six partition comparisons and twelve
successive-edit cases across cave/mountain sites at 960, 1056 and 1280. It also
checks invalid intervals, cancellation and the Y normal halo.

- Eight aligned 32 m slabs, and separately seven uneven slabs including 1 m cuts,
  reproduce the full-height oriented triangle **and normal bit** multisets exactly.
- Edits inside a brick, across a horizontal face, an edge and a 3D corner rebuild
  exactly 1, 2, 4 and 8 bricks. After every edit, retained plus replaced bricks
  match fresh full-height reconstruction of all four horizontal columns.
- Recorded reconstruction plus normals takes 1.03–22.01 ms across the twelve
  cases. These are individual observations, not percentile or end-to-end claims.
- The largest replacement is 46,042 triangles / 1,887,656 estimated render bytes.
  This remains significant work for packing, collision and upload.
- The existing 54-check candidate regression passes, including exact historical
  full-height mesh bytes, topology, normals, allocation failure and cancellation.
- Both extension variants build with Zig and prebuilt godot-cpp; zero SDK sources
  are rebuilt.

Reports and hashes are retained under `evidence/terrain_bricks/`.

## Bounded snapshots and worker integration

Sparse snapshot capture now copies only the vertical pages intersecting the
requested sample interval, including the positive normal halo. The worker carries
the bounds and uses them when determining whether a subsequent edit invalidates
its result. The native brick test verifies snapshot geometry/normal parity for all
partition intervals and asynchronous worker parity after the twelve edits. Separate
same-column edits demonstrate that a different Y interval preserves validity while
an overlapping interval rejects the result.

In a fixture with every source page present, a 32 m vertical request performs 27
page lookups and owns 222,580 payload bytes, versus 153 lookups and 1,254,772 bytes
for a full-height request. These are capture payload measurements, not total
process memory or an end-to-end latency ratio.

Godot exposes `experimental_snapshot_submit_brick(x,z,size,token,revision,y_begin,y_end)`.
Completed packets include `y_begin` and `y_end`. The original five-argument submit
method retains full-height behavior. The old column encoder rejects partial-height
packets because its ownership and block emission still cover the full column.
All 22 release-extension bridge checks pass, including bounded metadata, invalid
bounds, old admission/stale/shutdown controls and rejection by the column encoder.
The existing 36-case sparse snapshot regression also passes.

Evidence for this extension is under `evidence/terrain_brick_snapshots/`; initial
direct reconstruction measurements above remain in their original evidence folder.

## Remaining integration

Gameplay still requests full-height terrain. Cached ownership and scene publication
must carry vertical bounds before
this reduces gameplay mining work. It does not solve distant LOD reduction or the
simplifier defects recorded in `TERRAIN_REGION_AGGREGATION.md`. Collision, shading,
GPU upload, render batching and the automated fullscreen mining/travel workload
remain necessary; this native component result does not qualify the mining fix.
