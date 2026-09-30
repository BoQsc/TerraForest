# Boundary and topology decision probe

The release probe runs in about five seconds with no native/runtime changes.
It checks mountain, cave, two world-edge locations and an excavation at the
intersection of four regions. At each site it builds one 64 m fine mesh and four
32 m regions at steps 1, 2, 4 and 8: 85 native queries total.

Results: **77 checks pass, one topology gate fails.** The test intentionally exits
1 until the defect is fixed; successful partition comparisons are not acceptance
of the underlying mesh.

- The four fine child triangle multisets exactly equal the parent fine surface,
  including winding and duplicate counts. Raw float position bytes are compared,
  with no tolerance that could hide a crack.
- Child collision triangles exactly equal that same parent fine surface. The
  packet format intentionally omits collision faces for 64 m meshes, so the
  parent render triangles are the oracle. An initial version incorrectly compared
  against the empty parent collision channel; that test error was corrected.
- Open geometric edge multisets remain unchanged under interior simplification
  at every tested step. World-edge cases include empty out-of-world children.
- The cave parent already has **36 triangles with repeated vertex positions**,
  necessarily zero area, and **two indexed edges with more than two incident
  triangles**. Position-based welding finds 26 overused edges, including zero-length
  ones. The fine 32 m child at (960,960) reproduces 24 degenerate triangles and both
  indexed-edge defects. They exist without partitioning or simplification.

This is stronger than byte parity: parity alone faithfully preserves these
existing defects. The probe does not yet check every zero-area configuration,
vertex-link topology, orientation consistency, self-intersection, normals/shading,
geometric error or mixed-size T-junctions.

## Distant geometry constraint

Total triangles in the four 32 m children:

| Site | Step 1 | Step 2 | Step 4 | Step 8 |
|---|---:|---:|---:|---:|
| Mountain | 9,864 | 3,924 | 2,390 | 1,918 |
| Cave | 34,490 | 28,736 | 27,214 | 26,802 |
| Edited corner | 10,128 | 10,128 | 10,128 | 10,128 |

The edited case gets no reduction. Inspection of `simplify` shows edited sample
pages and their neighboring support pin vertices against collapse. That preserves
detail but cannot serve as a scalable distant representation of extensively edited
terrain. Cave/steep-surface protection also restricts reduction.

## Decision

### Isolated failure mechanisms

The public density sampler gives these values in cyclic order around shared
horizontal lattice faces (seed 1703, no edits):

| Face origin (x,y,z) | (0,0) | (1,0) | (1,1) | (0,1) |
|---|---:|---:|---:|---:|
| (963,56,989) | -0.385383 | +0.045502 | -0.017482 | +0.269484 |
| (964,55,991) | -0.253205 | +0.274439 | -0.022715 | +0.153343 |

Both faces have four solid/empty crossings. In `extract_vertices`, a cell gets
one averaged representative regardless of how many surface pieces it contains.
`connect_patch` connects representatives around each crossing lattice edge.
Here that creates four incident triangles on the same dual edge. The second
edge has three incident triangles in the retained child because its fourth lies
beyond that child's boundary. The parent still exhibits the defect.

Separately, the density at (985,61,963) is exactly zero. Edge interpolation reaches
that lattice corner, producing multiple coincident representatives and zero-area
triangles. The report retains the exact sample and defective edge positions.

Offline removal of every repeated-position triangle leaves **both indexed
overused edges** in the parent and retained child. Thus filtering degenerate
triangles is insufficient. The two failure cases must remain independent
regressions for any replacement: a consistent zero-value convention and a
representation/connectivity rule that resolves the alternating-sign face.
Do not weaken the topology gate to make cleanup look like a mesher fix.

### Adoption constraint

Region ownership and boundary pinning are useful starting points; they do not
require discarding all existing systems. However, do not integrate a region-based
runtime around this mesher unchanged. The next mesh prototype must handle the
retained cave topology defect and reduce edited/distant geometry under an explicit
error criterion. Removing degenerate triangles alone cannot establish correct
topology, and simply unpinning edited vertices risks destroying caves or edits.
These gates precede streaming integration and graphical performance acceptance.

```text
python tools/probe_terrain_boundaries.py --godot PATH
```

`docs/evidence/terrain_boundaries/` retains the report with source/DLL hashes,
engine log, and the compressed failing 32 m cave packet. This is a native geometry
probe, not GPU, collision-engine behavior, multiplayer or endurance qualification.
