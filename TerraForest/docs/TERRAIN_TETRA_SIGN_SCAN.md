# Tetrahedral candidate: skip homogeneous-cell construction

The isolated native prototype now checks the eight density signs before building
the cell's eight positions and global edge endpoint IDs. A cell whose signs are
all equal emits no tetrahedral surface, so this avoids unnecessary construction
without changing extraction order or interpolation. Mixed cells use the original
six-tetrahedron path. No runtime DLL or gameplay setting changes.

The probe retains the original loop as a same-field control. It runs five paired
measurements per fixture, alternating which implementation runs first across
repetitions and fixtures. Every pair compares all position and index bytes.
All 75 pairs match. All 15 output hashes also match the immutable original
candidate evidence. The complete probe passes 21 checks, including topology,
exact fine partitions and parity with authoritative quantized field samples.

| Fixture | Control median meshing ms | Sign-scan median meshing ms |
|---|---:|---:|
| Cave 32 m parent | 13.17 | 10.01 |
| Mountain 32 m parent | 7.73 | 3.61 |
| Edited mountain 32 m parent | 8.40 | 4.24 |

All fifteen fixture medians improve, with control/candidate ratios 1.25–2.16.
The sum of medians falls from 57.11 to 34.52 ms, a 39.6% reduction. That sum is a
corpus statistic, not a measured frame or transaction. Raw samples are retained;
they contain timing noise. This is a warm-field, single-process microbenchmark,
not a cold-cache, parallel-worker or loaded-game guarantee.

Sampling is unchanged and measured separately. Full-height density buffers and
the crossing hash map remain; this change does not establish a memory budget or
solve sparse sampling. Both implementations remain in the diagnostic executable,
so its total memory/time includes control and validation overhead.

The candidate still changes interpolation/zero convention relative to the old
mesher. Its field residual, geometry volume, LOD error, materials, normals,
lighting, collision integration and graphical performance are not qualified.
Preserving candidate hashes proves this optimization did not alter that geometry;
it does not make the candidate a drop-in terrain replacement.

Run `python tools/probe_terrain_tetra.py`.
The report and source/executable/toolchain hashes are retained in
`docs/evidence/terrain_tetra_sign_scan/`. Earlier tetrahedral evidence is unchanged.
