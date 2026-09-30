# Isolated tetrahedral geometry candidate

Implemented in C++ under `tests/native/terrain_tetra_probe.cpp`, compiled with
the pinned Zig toolchain. It is not linked into the game DLL. The executable
reads the existing native World, splits every cube into six consistently oriented
tetrahedra, and shares intersection vertices by canonical lattice-edge identity.
No third-party implementation is copied.

This tests an alternative interpolation and connectivity rule, not an optimized
replacement pipeline. Tetrahedral extraction is a documented approach, with
triangle quality/count tradeoffs discussed in
[Regularised marching tetrahedra](https://www.sciencedirect.com/science/article/pii/S009784939900076X).
That paper is background; this prototype does not implement its regularisation.

## What passed in the initial revision

Three fields (retained cave, mountain, edited mountain) each produce one 32 m
parent and four independent 16 m children, over y=0..256. All 18 checks pass:

- Each of 15 meshes has no duplicate face, no exact zero-area triangle, no geometric edge incident
  to more than two triangles, consistent winding along shared edges, connected
  manifold vertex links, and no open edge away from the domain boundary.
- Each of three child unions exactly equals its parent triangle multiset in
  world-space float bytes, preserving winding and multiplicity.

Unlike the current Surface Nets output, the retained cave case passes these
tests. This is evidence that the replacement can address the known connectivity
problem while supporting independent fine regions. It is not exhaustive topology
proof: self-intersection, arbitrary density fields and other LODs remain untested.

## Shape and cost prevent adoption

Quantization matches the existing density scale of 1024 units. Exact zero samples
are treated as exterior with +0.5/1024 density for interpolation. This prevents
intersections landing exactly on a lattice corner in the tested cases. A small
scalar change does **not** establish a small geometric displacement in a field
with a weak gradient.

The prototype uses linear interpolation inside tetrahedra. It does not reproduce
the original trilinear field or original Surface Nets surface exactly. Evaluating
the original quantized trilinear field at generated vertices/triangle centroids
finds the following residuals; these are field units, **not a distance bound**:

| 32 m case | Sampling ms | Meshing ms | Triangles | Max vertex residual | Max centroid residual |
|---|---:|---:|---:|---:|---:|
| Cave | 40.63 | 13.47 | 40,858 | 0.302391 | 0.189875 |
| Mountain | 38.56 | 7.87 | 16,384 | 0.001231 | 0.001057 |
| Edited mountain | 35.95 | 8.13 | 17,100 | 0.235596 | 0.226505 |

Sampling currently traverses the full vertical range through World::sample,
including repeated height evaluation. Timings are single component observations;
they exclude validation, output writing, shading, material generation, collision
publication and rendering. This is deliberately a topology reference, not a claim
of a fast sampler. The final warm-toolchain test run took 3.29 seconds overall.

The retained current-mesher cave packet has 9,858 triangles, versus this candidate's
40,858. That raw 4.14x growth is not an exact algorithm comparison: the dense
candidate also extracts the bedrock underside, and the two meshers have different
patch-boundary ownership conventions. It nevertheless prevents assuming that
resolving ambiguity alone produces an efficient distant representation. There is
no LOD or simplification in the candidate.

**Do not adopt this candidate in gameplay.** It supplies a working topology
reference and strengthens the selection criteria for the production mesher.
The next comparison needs explicit geometric error, bounded sampling, reduced
distant geometry and the existing region-boundary tests. Neither its topology
passes nor the current mesher's lower triangle count decides that comparison.

## Reproduce

### Column sampling follow-up

The candidate now evaluates height once per XZ column and looks up each edited
16-sample page once per column/page band, instead of repeating those operations
for every Y sample. It still densely evaluates the full vertical range; no
samples or geometry are omitted. This code remains isolated in the prototype,
and directly reads the current native page layout rather than adding a runtime API.

The runner now passes 20 checks, including comparison of **all 1,730,895 quantized
density samples** with World::sample and byte-for-byte mesh hashes against the
committed initial prototype. Topology, triangle counts and field residuals remain
unchanged. The original report above is retained; this follow-up is stored in
`docs/evidence/terrain_tetra_column/`.

| 32 m case | Original sampling ms | Column sampling ms | Meshing ms |
|---|---:|---:|---:|
| Cave | 43.45 | 13.65 | 14.39 |
| Mountain | 38.24 | 9.12 | 7.49 |
| Edited mountain | 39.45 | 9.50 | 8.06 |

These are matched single-run observations, with original sampling first. They
are not percentiles or cold/warm order-controlled performance certification.
Array equality validation is outside both sampling and meshing timers. The cave
candidate now spends approximately 28 ms in these two stages in this run, still
excluding materials, lighting, collision publication and rendering. Geometry
growth, interpolation differences, dense sampling and absent distant LOD still
prevent adoption. This change establishes that repeated column evaluation was
avoidable overhead without changing the candidate's output.

```text
python tools/probe_terrain_tetra.py
```

The runner uses the project's pinned target, compiler flags and compiler cache.
The first build attempt used the default compiler cache and exceeded its 120 s
timeout; no compiler process remained. Reusing the project configuration resolved
that setup issue. No game DLL was rebuilt or replaced.

The report includes source hashes, toolchain lock hash, build command, executable
hash, mesh hashes, all topology checks and individual timings. Evidence and the
candidate cave mesh are retained in `docs/evidence/terrain_tetra/`. Candidate mesh
format: two little-endian u32 counts (vertices, indices), float32 XYZ vertices,
then u32 indices. This format is diagnostic only.
