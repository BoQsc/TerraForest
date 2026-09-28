# Exact adaptive block baking

The native block worker previously expanded every 16-cube chunk and its halo into
a 66-cubed byte occupancy array, regardless of the authored shapes. Ordinary
cube buildings therefore paid for quarter-block resolution needed only by stairs
and posts. The worker now selects the coarsest exact grid supported by the chunk
and its halo, then runs a separately compiled constant-stride baker:

| Occupancy shapes present | Interior grid | Occupancy scratch, including halo |
| --- | --- | --- |
| Cubes only (or separately emitted wedges/spheres) | 16 cubed | 5,832 bytes |
| Slabs, without stairs/posts | 32 cubed | 39,304 bytes |
| Any stair or post | 64 cubed | 287,496 bytes |

The scratch figures exclude face masks, output buffers and worker infrastructure.
This is a temporary bake optimization, not a reduced-detail rendering mode.
Vertex positions, material selection and tiled UVs retain world-unit spacing.
Halo inspection preserves fragments exposed by neighboring partial shapes.
Existing invalidation, immutable worker inputs, stale-result rejection, cache
budgets, shape geometry, collision generation and snapshot formats are retained.

Resident visual counts are exposed through `stats()` as
`bake_lattice_16_chunks`, `bake_lattice_32_chunks`, and
`bake_lattice_64_chunks`. Cached results carry the selected width. These counts
describe published meshes, not pending or deferred authored chunks.

## Matched output and timing evidence

Before modifying the native code, seven fixture outputs were captured using
commit `1e0319e031b3a6514ba4b8a8e78a00079b14fec9`, debug DLL SHA-256
`0bd016878112fe9c6c0e92b3f6ba9988c915621e3dcfdb744b9861aa3c78d655`.
Godot 4.7.2 Steam was used for the old and new runs. The committed reference
includes SHA-256 hashes of mesh positions and all surface-array bytes, covering
positions, normals, UVs, materials and indices. References must be present for
the test to pass; tests do not regenerate them.

All seven old hashes match the new debug and release outputs exactly. Both
variants pass 31 checks, including deterministic rebakes, expected grid choice,
a neighboring stair promoting the dependent cube chunk, and restoring the
coarse representation after that stair is removed by snapshot restoration.

The table shows median elapsed milliseconds from eight real rebakes of each
three-chunk fixture on a warm instance. A known occupied cell is removed and
flushed before each timed restoration. Timed work includes native authoring,
thread launch/join, baking and headless mesh publication. It excludes collision,
rendered frames and initial material creation. This is an offline CPU workflow,
not a frame-time or city-scale performance claim.

| Fixture | Old debug | New debug |
| --- | ---: | ---: |
| Hollow cube shell, alternating materials | 34.082 | 4.390 |
| Sparse cubes, alternating materials | 36.099 | 9.995 |
| Slabs | 34.254 | 18.248 |
| Stairs mixed with cubes | 45.414 | 46.464 |
| Posts mixed with slabs | 44.402 | 47.918 |
| Wedges and spheres | 31.673 | 11.371 |
| Cube chunk with neighboring stair | 23.625 | 17.950 |

Stairs/posts retain the original quarter-grid work; no speedup is claimed for
those cases. Short-run measurements vary with system scheduling. Release results
are retained separately; no old release timing baseline was captured.

The existing structure suite passes 280 checks in each binary variant. Its
51-chunk house/tower showcase retains 9,469 cells and 7,502 triangles, with
37 chunks on the cube grid, four on the slab grid and ten on the quarter grid.
The 1920x1080 fullscreen main-world suite passes all 148 checks, including player
support, stair flights, prefab placement, model doorway traversal, undo/redo,
vegetation exclusion, persistence and streaming away/back. Evidence and final
build fingerprints are in `evidence/block_lattice/`.

## Remaining scope

This does not reduce final triangle counts, increase the 2,048 authored-chunk
capacity, implement disk region eviction, add distant building LOD, or establish
high-speed collision readiness. Dense mixed-shape chunks still require the fine
grid and can produce large buffers. Physics cooking and mesh publication retain
their existing non-preemptible costs. City generation and long-duration workload
validation remain unfinished.
