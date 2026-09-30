# Mixed-size geometry: useful partition, incomplete dependency contract

The release-native probe covers a 256 m square with thirteen aligned quadtree
owners: three 128 m, three 64 m, three 32 m and four 16 m regions. Larger owners
use the existing runtime simplification step. It excavates at the shared corner
of the four fine regions and compares before/after meshes using exact float
position bytes and oriented triangle multisets.

Two roots are tested: mountain at (1280,1280), edit at (1296,1296); cave at
(768,768), edit at (976,976). The cave refinement path moves through northeast
children before reaching its fine owners. Both roots and every child align to
the runtime quadtree lattice. An exploratory unaligned cave partition passed
local replacement; it was superseded by this aligned fixture and is not evidence
for runtime adoption.

## Results

**Ten checks pass, five fail; the runner intentionally exits 1.** All four mixed
cuts (two sites before/after) have exactly the parent's open-edge multiset. The
mountain has no duplicate triangles or overused geometric edges, and replacing
only its four fine owners equals a completely fresh mixed cut.

The cave cut fails duplicate-triangle and overused-edge gates before and after
the edit. It also fails exact local replacement: keeping old coarse siblings
leaves 1,174 old triangles and omits 3,928 triangles relative to a fresh rebuild.
Three 64 m owners change: (896,896), (960,896), and (896,960).

Inspection of the existing simplifier shows it pins vertices when a neighboring
16 m sample page has edits. Thus a small excavation can change coarse reduction
outside the four fine owners. The observed neighbor changes are consistent with
this dependency; this experiment does not independently disable pinning to prove
it is the sole cause. The replacement needs an explicit contract for these
dependencies, rather than assuming density-intersecting owners are the whole set.

This mismatch is **not proof of a visible crack or missing physical surface**:
the fresh cut can select a different approximation of unchanged density. Exact
fresh-rebuild equivalence is the tested criterion. Relaxing it requires an
explicit approximation/error contract, which the current simplifier lacks.
Open-edge equality is also narrower than a manifold/self-intersection proof.

| Post-edit result | Mountain | Cave |
|---|---:|---:|
| Parent triangles | 11,336 | 63,454 |
| Mixed-cut triangles | 31,350 | 81,990 |
| Triangle multiplier | 2.77 | 1.29 |
| Parent encoded bytes | 488,212 | 2,579,932 |
| Mixed-cut encoded bytes | 1,710,100 | 4,682,452 |
| Parent native build ms | 281.21 | 1,112.02 |
| Four local native builds ms, summed | 7.77 | 77.14 |
| Complete mixed-cut native builds ms, summed | 225.57 | 635.21 |

Single-run timings are diagnostic, not distributions or achieved interaction
latency. Encoded byte differences also include collision data on fine owners,
which the large parent omits. This is substantially less geometry amplification
than fine regions everywhere, but draw-call cost and visual quality are untested.

## Decision

Keep adaptive region ownership as the direction to investigate. Do not integrate
the current mesher unchanged or claim four-owner replacement works universally.
Next resolve or explicitly represent simplifier dependency bounds and retain
the aligned cave case as a counterexample. The earlier mesher topology blocker
remains; keeping identical invalid geometry is not correctness.

This tests geometry only. It does not perform a live parent-to-children transition
or validate normals, lighting, materials, error to the density field, physics,
GPU performance or endurance. No production code changes are introduced.

Reproduce with `python tools/probe_terrain_mixed_cut.py --godot PATH`.
The 56 native requests, mesh hashes, source/DLL hashes, failure coordinates and
report are retained in `docs/evidence/terrain_mixed_cut/`.

## Dependency isolation follow-up

The probe now additionally builds all six 64 m neighbors at step 1 before and
after the edit. **All six full-resolution triangle multisets are unchanged.**
In particular, the three changing cave neighbors have identical extracted
surfaces but different simplified geometry. This rules out changed extracted
surface positions/connectivity as the explanation for this witness; the
history-dependent simplification decisions are responsible for the difference.

A conservative experimental dependency projection takes the native edit bounds,
rounds to 16 m pages, expands by one neighboring page and two cells for extraction
support, and selects intersecting simplified owners. It includes four fine owners
in both cases and the three additional 64 m cave neighbors. Replacing that set
exactly matches the fresh mixed cut in both fixtures.

This is a tested candidate bound for two fixtures, not a universal proof. It
projects away Y and can over-invalidate. It uses native edit bounds, not merely
the brush radius. The raw bounds and selected owners are retained in the report.

**Reject expanding synchronous invalidation as the solution:** the cave's seven
selected builds total **199.07 ms**, versus **69.91 ms** for its four fine regions,
before main-thread publication or queueing. This exceeds the existing 150 ms
whole-interaction rejection ceiling. The mountain remains at four regions and
6.37 ms. These are single-run native diagnostics, not FPS or latency distributions.
The extended runner has 19 passing checks and six failures, including the new
latency rejection; it intentionally exits 1.

The architectural requirement is now more specific: distant simplification must
not become synchronous edit work merely because edit-history metadata changed
near an otherwise unchanged extracted surface. A replacement must base retained
geometry validity on explicit field/approximation dependencies, or schedule a
validated distant refresh separately. This does not authorize simply removing
vertex protection, which could erase cave or excavation detail.

Follow-up evidence (68 native requests) is retained separately under
`docs/evidence/terrain_mixed_dependencies/`; the earlier evidence is unchanged.
