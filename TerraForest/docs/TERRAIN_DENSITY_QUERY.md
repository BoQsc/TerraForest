# Experimental bounded density query

`experimental/density_ray.hpp` adds an allocation-free C++ query over an immutable
quantized trilinear lattice. It clips a finite segment to the current world bounds,
traverses crossed cells in order, constructs the cell's cubic along the segment,
and partitions it at derivative roots before finding the first zero. Same-sign
cell endpoints therefore do not automatically imply no hit. Tangencies and starts
on a zero surface are included; a start in solid searches for the first exit.

The result distinguishes hit, miss, work_limit, cancelled and invalid_input. Cell
visits are bounded (default 4,096); each cell reads eight samples and each root
interval uses at most 60 bisection iterations. Cancellation is checked before each
cell and again before returning a hit. It constructs no Godot objects. Finite input
coordinates are admitted within +/-10,000, matching the current bounded world
context; this is not an unbounded-world interface.

`python tools/probe_terrain_density_rays.py` passes 18 analytic controls covering
multi-cell traversal, reversal, clipped entry, three roots in a cell, tangency,
shared cell boundaries, surface/inside starts, world exit, miss, zero-length and
nonfinite input, invalid samples, exact/insufficient budgets and late cancellation.
All 22 frozen physics-miss segments also return hits within the unchanged 2 mm
tolerance. The earlier bracket diagnostic and air/solid controls still run.
Evidence: [retained report](evidence/terrain_density_query/terrain_density_rays.json.gz).

Coefficient normalization avoids magnitude-dependent overflow in the derivative
solver. Numerical zero uses 64 double machine epsilons relative to the largest
coefficient. This is an explicit numerical convention, not exact arithmetic:
near-tangent, near-multiple-root and nearly simultaneous boundary adversaries
still need broader coverage. No performance/headroom claim follows from these
small tests.

The header is not registered in the game extension. Missing work includes runtime
worker ownership, stale-world rejection, hit normals/materials, selection against
other object types and integration into the player interaction path. Trilinear
field versus tetrahedral rendered-surface approximation remains unresolved. Keep
physics triangle-ray failures recorded; this provides a separate query candidate,
not a claim that those engine queries were repaired.
