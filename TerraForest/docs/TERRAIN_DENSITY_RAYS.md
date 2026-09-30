# Density crossings at frozen triangle-ray misses

Code inspection found no exposed terrain-density interaction raycaster. The scene
interaction path currently calls engine physics rays (structures/block_queries.cpp);
native terrain has density sampling and lighting traversal helpers, not the assumed
existing general interaction query. This experiment therefore tests field suitability
before adding such a runtime system.

`python tools/probe_terrain_density_rays.py` reconstructs the original seed and edit
state for all 22 frozen missed faces: 21 from displaced-zero geometry and one from
the exact-zero variant. It evaluates the quantized lattice with trilinear
interpolation, preserving actual zero values, and bisects a sign-bracketed 0.04 m
segment through each original triangle center. It does not use physics triangles.

All 22 segments bracket a crossing within the existing 0.002 m tolerance. For the
21 bottom-plane slivers the measured offset is 0.000488043 m and root density is
zero. For the remaining mountain face, float position refinement reaches the
center with field residual -7.28905e-6; this is numerical convergence, not a claim
of an exact mathematical root. Shifted segments 0.1 m along either normal direction
have respectively positive and negative endpoint densities in every case.

The [retained report](evidence/terrain_density_rays/terrain_density_rays.json.gz)
contains inputs' source hashes, field values, offsets and controls. Passing these
short brackets supports a density-based interaction query candidate. It does not
prove a general raycaster, a unique or first crossing, absence of tangent roots,
or matching all rendered surfaces. The tetrahedral surface and trilinear field
are different interpolants; previously measured approximation error remains open.

Next a runtime query needs bounded cell traversal, first-root handling within each
cell, explicit work-limit/cancellation statuses, and tests for inside starts,
tangency, multiple roots and world boundaries. Do not implement unrestricted
fixed-step sampling and infer that it cannot miss thin features. Physics ray
qualification remains failed, and no gameplay path changed in this experiment.
