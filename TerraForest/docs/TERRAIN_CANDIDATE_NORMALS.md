# Canonical normal reference: correctness passes, runtime adoption rejected

The isolated candidate now has a reference normal builder. At each world-space
vertex it evaluates the analytic gradient of the canonical containing cell's
trilinear density interpolant, then normalizes. Cell choice is independent of
region ownership; shared positions therefore use the same samples and arithmetic.
This is a shading normal, not the geometric normal of the tetrahedral surface.

`python tools/probe_terrain_tetra.py` passes 51 checks. The fifteen fixtures all
produce finite unit normals. At each of the three sites, the four child meshes'
position-to-normal maps exactly equal the parent map, including byte-identical
normals at shared child boundaries. Existing geometry reference hashes match.
Evidence: [retained report](evidence/terrain_candidate_normals/terrain_tetra_probe.json.gz).

The implementation performs eight World::sample calls per vertex. The retained
single-run 32 m cave result is 27.85 ms for 20,878 vertices / 167,024 calls; the
16 m cave cases take 5.74 to 8.72 ms. These are diagnostic timings, not repeated
performance qualification. They are sufficient reason not to adopt this direct
sampling implementation into the live pipeline: normals alone consume a material
part of the edit budget. Reuse of sampled density data is the next implementation
requirement; preserve this independent scalar reference for comparison.

The containing-cell rule reads one sample beyond a region's positive boundary
when a vertex lies exactly on that boundary. Geometry-only invalidation is thus
insufficient for these normals; their positive sample halo needs explicit tracking.
The current header has cancellation, checked output allocation and zero-gradient
failure paths, but their normal-specific fault controls are not yet qualified.
Normals can change discontinuously between lattice cells because trilinear
gradients are not generally continuous. No visual acceptance, material blending,
lighting, GPU upload, collision integration or mixed-resolution qualification is
implied. The header remains outside the game extension.
