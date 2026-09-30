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

## Shaded packet and collision conversion

`experimental_snapshot_encode_brick(packet,x,z,size)` converts a fresh bounded
result into existing v5 render/material/lighting channels and collision faces,
wrapped with explicit 3D `origin`, `extent`, revision and epoch. The legacy column
encoder continues to reject partial-height input. Conversion validates every
position against the owned volume. Unit-block emission filters by the same
half-open Y interval, retaining neighbor occlusion across the cut; a block at a
different height is not accidentally emitted in every brick.

The headless snapshot-mesh test now constructs actual ArrayMesh resources and
native collision recipes for adjacent bricks. A block-removal case verifies the
newly exposed neighboring face. A real density excavation centered on Y=32
verifies cavity-wall ray hits on both sides of the join. In both cases old
collision remains active while replacements are prepared, then both replacements
are activated together. Empty replacement geometry creates no empty ArrayMesh
surface. This initial fixture established conversion before the main-stream
integration described below.

This does not resolve the earlier tiny-face collision qualification failures or
establish a general collision guarantee. No graphical appearance or frame-budget
claim follows from a headless two-brick test. Evidence for this conversion is in
`evidence/terrain_brick_publication/`; ordinary debug/release bridge fingerprints
still match the published baseline after the bounded block-emission change.

## Main worker/stream integration and fullscreen result

`--brick-terrain` now routes in-world 16/32 m columns through bounded snapshot
jobs in the existing backend. Initial columns contain eight 32 m height ranges.
The stream rebuilds only ranges intersecting the edit dependency box, stages
their collision pieces under the existing frame budget, and moves unchanged
mesh/collision nodes into the replacement column at commit. Residency bytes count
retained children once. Deferred lighting updates child attributes without
rebuilding their geometry or collision. No persistent disk brick cache is added.

The real worker publication fixture checks held and overlapped preparation:
each edit replaces eight bricks and retains 24, with old physics active until
commit. It verifies complete ownership, exact cache accounting, changed surface
hits, deferred lighting completion and retained node identities. The earlier
full-column snapshot worker fixture also passes.

The existing 136-edit mining/travel workload was run with this path selected,
at verified 1920x1080 fullscreen/full render scale on the GTX 1060 Max-Q:

| Phase | Frame p99 ms | Edit publication p95 ms |
| --- | ---: | ---: |
| Baseline | 16.741 | — |
| Compact control | 24.262 | 167.976 |
| Expanding excavation | 19.729 | 201.529 |
| Travel | 16.874 | 451.044 |
| Return control | 16.700 | 69.814 |
| Recovery | 26.353 | — |

The run **fails five gates**, with no runtime errors and no measured frame above
50 ms. It is a single observation, not a matched speedup comparison or endurance
qualification. The slowest recorded travel patch remains an old-path 256 m edit
rebuild at (1280,1280), taking 303.522 ms. Brick ownership is operational in the
main stream; that fact alone has not fixed overall edit latency or headroom.

Reproduce with `python tools/foundation_scaling.py --terrain bricks --scales 1
--godot PATH`. Mode-specific report folders retain the launch command and source
hashes. Evidence is retained in `evidence/terrain_brick_stream/`.

## Remaining work

The option remains experimental and off by default. Large patches still use the
old reconstruction path. It does not solve distant LOD reduction or the
simplifier defects recorded in `TERRAIN_REGION_AGGREGATION.md`. Mixed legacy/candidate
joins remain unqualified. Collision cooking/attachment also consumes multiple
publication frames in the local cases. The failed fullscreen workload must pass
before claiming the mining fix; longer travel, residency/cancellation pressure
and endurance qualification remain outstanding.
