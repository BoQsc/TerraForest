# Reject direct legacy-to-candidate local replacement

The retained-partition implementation preserves the source triangles, but this
does not make its boundaries compatible with newly reconstructed terrain.
The new targeted join probe rejects all eight tested sides. Keep automatic
mining partition/replacement disabled until a transition is implemented and verified.

The test builds a legacy 256 m / step-8 parent, partitions it recursively to an
interior 32 m child, and compares its boundary segments with snapshot tetrahedral
geometry at the same location. Sites are (1376,1376) and (960,960). A radius-2.5
excavation at each child's center changes the world revision without reaching
the child boundaries. Candidate neighbors are then built against the edited world.

| Site | Boundary discrepancy above Y=2, four sides (m) |
| --- | --- |
| Mountain | 0.10759, 0.14272, 0.11116, 0.07620 |
| Cave | 0.17200, 0.19699, 0.17200, 0.13452 |

These are endpoint/midpoint distance witnesses to the other mesh's boundary
segments, hence lower bounds on geometric separation, not whole-surface Hausdorff
error or a screenshot measurement. They exceed the 1 mm admission tolerance.
The test also retains full-height results: candidate boundary components around
Y=1.000488 have no matching retained component, producing much larger distances.
The above-Y=2 table separates that world-bottom representation difference; it
does not remove it from the rejection gate.

All eight candidate-to-candidate neighbor edge multisets match bit for bit.
Before/after interior-edit boundary discrepancies are at most 0.0000153 m under
the sampling calculation. Thus these witnesses distinguish cross-representation
mismatch from a failure of candidate neighbor agreement in these fixtures.
They do not prove every candidate seam, winding, topology, normals or collision.

## Next implementation constraint

Retained partitioning can reuse an existing surface and preserve its internal
seams; it cannot act as the transition algorithm. Do not attach a newly mined
candidate patch directly to its legacy sibling or hide the gap with unchecked
skirts. Local and distant representations need a shared boundary construction,
or explicit transition geometry with verified topology and approximation bounds.
The existing staged publication and partition allocation/cancellation work remains
usable once that geometric contract is met. No runtime defaults change here.

Run `python tools/probe_terrain_retained_join.py --godot PATH`.
It intentionally exits 1 while these admission failures remain. Reports and
witness coordinates are retained in `evidence/retained_join_rejection/`.
