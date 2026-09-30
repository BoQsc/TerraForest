# Cubic near-tangent correction

The numerical suite now includes 34 genuine cubic restrictions in addition to the
33 quadratic cases. Cubics multiply a near-tangent quadratic by a linear factor,
vary coefficient scale across 1e-9, 1 and 1e9, and include a repeated root at 1/3.
The Python oracle evaluates the actual binary input coefficients with 80-digit
Decimal arithmetic, partitions at derivative roots, and refines monotone intervals.
Its 1e-65 relative zero threshold is far below this suite's input perturbations.

The [before report](evidence/terrain_cubic_numerics/before.json.gz) records seven
cubic failures: six false hits and one first-root error. The previous approximate
zero admission and coefficient normalization caused the tested discrepancies.
The candidate now keeps original coefficients and uses extended precision for
derivative roots, polynomial evaluation and at most 80 bisection steps. It no
longer admits a cubic hit merely because the evaluated density is near zero.

`python tools/probe_terrain_ray_numerics.py` now passes all 67 cases, with hit
fractions within 1e-9 of their references. `python tools/probe_terrain_density_rays.py`
also passes all 18 traversal controls and 22 frozen physics-ray locations.
Retained [after report](evidence/terrain_cubic_numerics/after.json.gz) and
[traversal report](evidence/terrain_cubic_numerics/terrain_density_rays.json.gz).

This is finite-precision evaluation, not a formal exact-predicate guarantee.
Arbitrary nearly repeated cubics, coefficient formation during traversal,
cross-platform long-double behavior and performance still need qualification.
The query remains experimental and unregistered in gameplay. No engine physics
behavior, collision geometry or existing ray acceptance threshold changed.
