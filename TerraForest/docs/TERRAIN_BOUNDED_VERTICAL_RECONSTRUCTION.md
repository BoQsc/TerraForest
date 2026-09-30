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

## Evidence

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

## Remaining integration

Gameplay still requests full-height terrain. Sparse snapshot capture, worker
requests, cached ownership and scene publication must carry vertical bounds before
this reduces gameplay mining work. It does not solve distant LOD reduction or the
simplifier defects recorded in `TERRAIN_REGION_AGGREGATION.md`. Collision, shading,
GPU upload, render batching and the automated fullscreen mining/travel workload
remain necessary; this native component result does not qualify the mining fix.
