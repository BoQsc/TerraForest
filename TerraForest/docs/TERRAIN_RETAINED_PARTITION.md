# Retaining surrounding terrain during local replacement

`TerrainCore.experimental_partition_mesh(packet)` splits an existing v5 terrain
packet into four quadtree children in native code. It reads no world state and
performs no density sampling, shading or simplification. Original interior
vertices remain indexed; only boundary intersections add vertices. Position,
normal, material weights and visibility channels are interpolated along original
triangles. A triangle lying entirely on a split plane has one owner.

This supplies retained surrounding geometry for the next local-replacement
integration. It is not called automatically by the runtime yet. Connecting a
newly reconstructed edited region to this retained surface remains unfinished;
partitioning an old surface alone does not prove that connection is watertight.
The old mesher's topology and approximation errors are retained, not repaired.

The native packet input is limited to 64 MiB, one million vertices and 1.5 million
indices. Output growth has explicit count and size rejection. The 128 MiB working
allocation check occurs after a grow operation and is **not** a hard peak-memory
allocator budget. Outputs are all-or-nothing; the caller retains its original
packet on rejection. Requests do not yet have cooperative cancellation. These
limitations need resolution before broad runtime use.

## Validation, 2026-09-30

19 release-extension checks pass: area preservation, recursive partition, linear
visibility interpolation, unique ownership of a coplanar wall, exact matching X/Z
boundary-edge multisets, indexed interior retention, and malformed packet rejection.
Real mountain and cave packets were generated using the current 256 m / step-8
mesher. These checks are headless; they do not prove visual equivalence, collision
behavior, manifold geometry, dynamic edits, allocation-failure recovery or FPS.

| Source | Split ms | Original bytes | Four child bytes |
| --- | ---: | ---: | ---: |
| Mountain (1280,1280) | 2.112 | 268,596 | 309,696 |
| Cave (768,768) | 16.347 | 2,196,876 | 2,269,224 |

These are single-run diagnostic times, not latency bounds or an end-to-end speedup.
Children retain the source LOD step; coarse children do not acquire fine collision
or become valid player-residency evidence merely by becoming smaller owners.

Both native variants build against prebuilt godot-cpp. Reproduce with
`python tools/probe_terrain_partition.py --godot PATH`.
Source fingerprints and the report are in `evidence/retained_partition/`.
