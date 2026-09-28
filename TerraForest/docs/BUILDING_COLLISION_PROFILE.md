# Dense building collision admission baseline

The current native building runtime calls `create_trimesh_shape()` for an entire
nearby mesh chunk, then attaches one body/shape. Limiting creation to one chunk
per frame does not bound triangle count or main-thread time.

`tests/building_collision_profile.gd` isolates admission from mesh baking. It
authors and bakes one 16-cubed chunk with collision disabled, then measures eight
collision enable/disable cycles without rebaking. Each admission is checked by
an actual physics ray against the native authored-shape ray. Nine correctness
checks pass in both debug and clean release projects. These checks do **not**
mean the timing is acceptable.

Godot 4.7.2 Steam, headless CPU measurements, existing Windows DLLs from
`2c89e38`. Times include triangle-shape creation and attachment or destruction;
they exclude rendered presentation and do not establish full simulation cost.

| 4,096-cell chunk | Triangles | Debug admission median/max ms | Release admission median/max ms |
| --- | ---: | ---: | ---: |
| Solid cubes | 12 | 0.101 / 0.782 | 0.146 / 0.611 |
| Stairs | 7,236 | 12.913 / 17.694 | 10.496 / 16.211 |
| Spheres | 491,520 | 1,335.592 / 1,667.592 | 1,362.032 / 1,827.883 |

Sphere collision removal also took median 7.107 ms debug / 7.394 ms release.
The existing mesh byte budget can reject a dense chunk at small configured
limits, but the default budget admits this case. Budget rejection is not a
solution for usable nearby authored buildings.

## Consequence for the next implementation

Replace whole-chunk physics creation with bounded triangle pieces prepared from
native bake buffers, using explicit piece/triangle admission budgets. Expose
pending versus complete collision readiness separately from visual residency.
Do not expose partial collision as a completed traversable chunk. Invalidation
must retire all obsolete pieces, and changed geometry must never reuse stale
faces. Release also needs bounded work; destroying a whole dense body at once
can exceed the frame budget. Native authored picking must remain independent
of physics residency.

Tests must cover dense admission over successive frames, exact final shape
queries, edits while pieces are pending, travel away before completion,
resource reclamation, and player/high-speed readiness. A small timing baseline
or a count of one operation per frame cannot prove these requirements.

This commit adds measurement and evidence only. It does not fix the measured
stall. Current buildings must not be described as ready for arbitrary dense
shape workloads or high-speed travel. Raw reports are retained in
`evidence/building_collision_profile/`.
