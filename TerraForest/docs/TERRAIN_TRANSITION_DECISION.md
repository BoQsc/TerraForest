# Retain native coverage publication; reconstruction remains the blocker

The headless release probe drives the real worker, stream staging and native
coverage planner through a complete parent-to-mixed-cut-to-parent cycle on the
aligned mountain root at (1280,1280). **54 checks pass.** No production code is
changed by this experiment.

The root begins as one visible 256 m mesh. Thirteen replacement owners arrive
one at a time (three each of 128, 64 and 32 m, plus four 16 m regions). After each
arrival the real planner updates the visible cut. An independent 16 m occupancy
grid verifies all 256 cells are covered exactly once, with no out-of-root owner.
The parent stays active through the first twelve arrivals. Only the final owner
allows the planner to switch to the complete thirteen-region cut.

A real radius-2.5 excavation then rebuilds four fine owners through the worker
and publishes while preserving the mixed cut. The hidden parent is marked dirty.
When refinement flags are cleared to request coarsening, the planner refuses to
resurrect that stale parent. After a fresh parent completes, it switches back to
one owner and disables all hidden child visuals and collision layers. Worker
shutdown joins cleanly. The prior 35-check publication and 42-check real-worker
tests also pass after the shared fixture type change.

## Limits

The test explicitly selects split flags and child arrival order. It does not
exercise automatic distance scheduling, rapid travel, worker contention, cache
eviction pressure or many simultaneous root transitions. Fine-collision readiness
is checked after refinement; coarsening explicitly sets collision requirement off
to model a distant region. It does not authorize coarsening beneath a walking
player. The earlier worker fixture provides separate physics-ray coverage.

The occupancy check verifies region ownership, not triangles or visual seams.
The separate mixed-cut geometry probe remains necessary and still rejects cave
topology and dependency behavior. This test does not make the legacy mesher valid.
It is headless, with no draw/GPU, presentation, animation or FPS qualification.

Serial replacement preparation took 441 ms in the retained diagnostic run;
this includes polling and staging and is not claimed as fast refinement. The old
parent remains visible during that interval. Keeping old terrain visible is not
equivalent to completing an edit or supplying fine collision at a new destination.
The two older regression probes were rerun concurrently for correctness only;
their timings are not a performance comparison.

## Architectural consequence

Preserve the tested native coverage and staged publication mechanisms while
replacing the problematic reconstruction/LOD dependencies. A total planner rewrite
has no justification from these fixtures. The remaining work is to supply correct
bounded-cost local geometry and a separately budgeted distant representation,
then qualify their automatic scheduling and graphical behavior under load.

Run `python tools/probe_terrain_publication.py --transition --godot PATH`.
Reports, source/DLL hashes and the transition log are in
`docs/evidence/terrain_transition/`.
