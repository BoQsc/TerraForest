# Candidate fixed edge storage

The experimental tetrahedral region builder now uses a direct lattice-edge table
instead of a node-allocating hash map. The fixed six-tetrahedron split has seven
monotone edge directions. A lower endpoint and direction uniquely identify each
edge; two alternating height planes retain shared crossings between layers.

The table allocates `14 * (size + 1)^2` uint32 slots in one checked allocation:
60,984 bytes for a 32 m region and 16,184 bytes for a 16 m region. These are
reserved slots, not occupied crossings. This trades unused slots for predictable
storage and removes per-crossing allocation. Scratch is released before a
successful mesh is returned, and also on failure.

## Evidence

Run `python tools/probe_terrain_tetra.py`. The retained report is
[terrain_tetra_probe.json.gz](evidence/terrain_candidate_edge_table/terrain_tetra_probe.json.gz).
All 31 checks pass, including exact byte equality with the immutable fifteen-mesh
reference and the alternating-layer storage control.

A combined allocator control injects failure at each of 24 allocation calls in
one world-backed build, covering sampling, edge storage and output growth. Every
failure returns allocation_failed, discards partial output and leaves no tracked
buffers. Success retains only the two output buffers; their destruction releases
them. Two invalid crossing allocator hooks are rejected before allocation.
Separate output and sampler failure controls remain in the suite.

The paired timing control is now a full-height direct table, **not the previous
hash implementation**. Its timing ratio cannot establish a speedup over the old
hash map. Geometry equality remains a valid comparison.

## Limits and next gate

This remains an isolated native candidate, unregistered in the gameplay extension.
The checks do not prove process-wide OOM resilience: world storage, engine,
renderer and physics allocations are outside this test. Output growth can hold
old and new buffers simultaneously; there is no complete peak-byte admission
budget. Custom allocator lifetime and alignment remain caller obligations.

Do not expand optimization work on this candidate without a measured reason.
The next integration gate is a defined local edit/LOD dependency contract and a
complete edit-to-collision/publication path. Surface approximation, material and
normal generation, mixed-resolution geometry, integrated frame time and long-run
behavior remain unqualified.
