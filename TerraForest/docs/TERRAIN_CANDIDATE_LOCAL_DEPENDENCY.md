# Candidate geometry dependency contract

The experimental full-resolution mesher owns half-open cells but reads closed
sample extents: an owner at `(x,z)` of width `s` reads lattice coordinates
`[x,x+s] x [0,256] x [z,z+s]`. Both owners depend on a shared boundary sample.
An edit invalidates an owner when its inclusive visited sample box intersects
that extent. World::edit floors both brush bounds before visiting samples, so
the dependency predicate must do the same. Invalid bounds conservatively select
the owner. This predicate is experimental and not wired into gameplay scheduling.

## Measured control

`python tools/probe_terrain_tetra.py` now passes 32 checks. The retained
[report](evidence/terrain_candidate_local_dependency/terrain_tetra_probe.json.gz)
contains six fresh-world excavation cases: underground near the cave fixture and
on the mountain surface, each at an owner interior, edge and corner. Each case
builds nine 16 m owners before mutation and independently rebuilds all nine after.

| Placement | Selected owners | Changed owners | Unselected owners verified unchanged |
|---|---:|---:|---:|
| Interior | 1 | 1 | 8 |
| Edge | 2 | 2 | 7 |
| Corner | 4 | 4 | 5 |

Both sites produce these counts. Actual density mutation counts range from 223
to 895, ruling out empty-space no-ops. Every unselected mesh matches the fresh
mesh positions and indices byte-for-byte. Exact shared-boundary and fractional
bound controls also run natively. All existing immutable mesh hashes still match.

## Integration requirements and limits

This establishes a narrow geometry dependency test, not a scheduler, an LOD
solution, or a latency qualification. Only six excavation cases are covered;
addition, swept brushes, accumulated remote edits and mixed-resolution owners
still need integration coverage. The existing edit box is conservative, not a
minimal list of changed samples.

Do not reuse this predicate as the entire invalidation rule for the current
pipeline: its simplification and shading dependencies extend beyond this
candidate's geometry reads. Normals/materials must declare their own sample halo;
lighting must have separate revision/dependency handling. Coarse ancestors must
be marked stale without forcing synchronous reconstruction of their full extent.
Mixed-resolution publication must wait for compatible replacement boundaries and
collision readiness. Existing coverage publication tests support reusing that
machinery; they do not supply these missing contracts.
