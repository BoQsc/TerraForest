# Near-tangent quadratic rejection and correction

`python tools/probe_terrain_ray_numerics.py` tests 33 quadratic restrictions:
eleven positive/zero/negative offsets around a double root, each at coefficient
scales 1e-9, 1 and 1e9. The oracle uses the actual rounded input coefficients in
extended precision, rather than assuming the ideal decimal inputs survived rounding.
Hit fractions must agree within 1e-9.

The [before report](evidence/terrain_ray_numerics/before.json.gz) records seven
failures: six false tangent hits for strictly positive minima and one inaccurate
first root. The approximate zero tolerance in the general cubic path admitted
near misses, and normalization affected a closely spaced root pair.

Exact linear/quadratic restrictions now use a separate extended-precision solve
before coefficient normalization. Negative discriminants return miss; admissible
roots are ordered and the first is selected using a stable quadratic formula.
The [after report](evidence/terrain_ray_numerics/after.json.gz) passes all 33 cases.
The [query regression report](evidence/terrain_ray_numerics/terrain_density_rays.json.gz)
also passes the original 18 analytic controls and all 22 frozen physics-miss rays.
The tests use the pinned Zig Windows GNU target; other long-double implementations
have not been qualified.

This corrects the measured lower-degree failures. It does not prove the general
cubic near-tangent case: that path still uses its explicit numerical-zero tolerance.
Nearly repeated cubic roots, coefficient formation error, randomized traversal and
performance remain unqualified. The query is still outside gameplay. Do not infer
that every false-hit mechanism has been eliminated from these 33 passing cases.
