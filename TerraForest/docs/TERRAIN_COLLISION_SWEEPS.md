# Shape sweeps distinguish contact from ray-query failures

The isolation probe now runs sphere and capsule cast_motion queries against each
frozen missed triangle. Sphere radius is 0.25 m; capsule radius is 0.25 m and total
height 1.5 m. Each shape travels 4 m along the triangle normal from a separated
start, with zero query margin. A parallel sweep displaced 10 m tangentially is a
negative control. Fractions must satisfy 0 <= safe <= unsafe <= 1.

Commands:

```
python tools/probe_terrain_collision_isolation.py --godot PATH
python tools/probe_terrain_collision_isolation.py --exact-zero --godot PATH
```

The [retained evidence](evidence/terrain_collision_sweeps) records:

| Frozen input | Sweep queries | Centered hits | Displaced hits | Sweep failures |
|---|---:|---:|---:|---:|
| 21 original missed faces | 1,008 | 504/504 | 0/504 | 0 |
| Remaining exact-zero variant miss | 48 | 24/24 | 0/24 | 0 |

Counts include the three coordinate representations and four diagnostic scales
from the earlier isolation experiment. Both shapes also hit all original-size
faces. Ray tests still execute alongside sweeps and retain their failures; this
does not weaken or replace the ray acceptance criteria. Script exit success now
requires the expected sweep outcomes and valid fractions, not passing ray results.

The evidence narrows the diagnosis: small-face ray intersection failure does not
imply equivalent failure of shape sweeps in these fixtures. Do not describe the
ray misses as proof that player bodies fall through the world. Conversely, these
isolated queries do not prove CharacterBody movement, contact stability, stacks,
high-speed rigid bodies or sustained simulation. No rendered/FPS test ran.

Next separate the terrain-interaction query contract from engine contact handling.
Qualify the existing authoritative density query against the frozen ray locations
before redesigning geometry solely to satisfy a triangle-ray tolerance. Preserve
topology and partition requirements and keep ray robustness explicitly unresolved.
