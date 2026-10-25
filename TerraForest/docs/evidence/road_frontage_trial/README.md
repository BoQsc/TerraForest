# Archived frontage-road experiment — rejected as a solution

The user rejected this preview on 2026-10-25 and requested the original game
without its preview label. The active scene, launcher, tests and native changes
were removed; source and both DLLs are back at the pre-preview baseline. The
interactive session closed normally and all 291 Wild_Hills files were unchanged.
The commands and implementation described below are historical evidence from
`bdb1c501`, not available current launch instructions. Preserve the evidence,
but do not promote these passing measurements over the user's rejection.
At most this is a future local town road type, not a solution to general block
gaps. The next design preference is some submergence over large floating gaps;
no new placement policy was enabled as part of the rollback.

2026-10-25. This replaces the rejected automatic-support direction with a
generation-only comparison. No placement override, support blocks, per-block
terrain edits, changed lattice, new building shapes or redesigned houses.

## Historical preview

Run `python tools/review_road_grades.py` from TerraForest. One game process/window
generates a temporary seed-1703, profile-21 comparison. F6 closes the in-memory
world and regenerates the other grading mode in that same window. F7 visits the
other street. Normal development block placement/removal is available. Switching
modes discards preview edits; nothing here is a player save.

This is a newly generated four-building comparison near `(977, 35, 1105)`, NOT a
rewritten Wild_Hills save or its exact original eight-building market. Both modes
use the same four unmodified approved assets (B2, A2, A2, B1). Their site positions
and entrance grades are fitted to each road plan before baking. The roads use the
same horizontal layout in both modes. Mainline generation and the installed
gameplay pack do not enable the experiment. The existing optional 30 cm road
remapping experiment remains separate and unapproved.

## Native implementation and bounds

Only explicit `frontage_trial` road descriptors enter the native proposal. The
existing `TerrainCore.plan_streets` result is otherwise unchanged. The trial
coordinates junction grades, plans two 52 m near-level building frontages at
integer + 0.08 m, and puts cubic elevation transitions in the 26 m end sections.
Connecting streets remain smooth terrain. The longest observed grade is 5.77%.

Candidate junctions vary by at most one integer level from the original solver.
Search is bounded to eight roads/five junctions; the review uses four/four and
finds a profile on junction attempt 28. Axis-aligned roads and endpoint junctions
only are supported; unpartitioned interior crossings are rejected. Half-metre
surveys include the 7.5 m half-width support/transition corridor and end caps.
The selected road survey reports at most 2.444 m cut and 1.428 m fill, within the
existing 3 m / 2 m limits. These are sampled natural-surface measurements, not a
proof over every unsampled point of terrain.

Optional native lot frontage intervals constrain entrances during candidate
search rather than rejecting a best lot after it has drifted onto a ramp.
House foundation/approach grading, road support, asphalt and paving beds are all
in the initial master bake, before any building is published. The native field
is reused by ordinary meshing, collision, editing and binary snapshots.

Sidewalks retain the trusted individual upright upper-quarter concrete plate.
The preview adapter supplies integer plate-top grades for flat road sections;
ramps stay editable terrain. It neither stretches nor rotates a plate diagonally.
The prototype deliberately does not introduce more shapes.

Planning runs in a worker and baking uses the existing native initial-earthworks
worker, not per-frame terrain logic. Native terrain and prefab transactions own
geometry and publication; review GDScript coordinates the scene and controls.
The proposal has 138 master stamps versus 98 for its baseline, mainly because
more level road length admits plates and their beds. This is NOT a generation
performance improvement. Repeated candidate surveys could be cached further;
whole-world runtime, generation throughput and memory remain unqualified.

## Measured contact and limitations

The integrated test samples both 104 m roads at three lateral tracks, with nine
native collision rays per metre footprint. It separately reports the building
frontages and the entire roads; transition failures are not excluded from the
whole-road result.

| Measurement | Baseline grading | Proposed grading |
| --- | ---: | ---: |
| Frontage footprints within 15 cm gap | 203 / 312 | 312 / 312 |
| Frontage footprints over 50 cm gap | 60 | 0 |
| Worst frontage gap | 87.21 cm | 10.71 cm |
| Maximum frontage burial | 13.32 cm | 8.09 cm |
| Entire-road footprints within 15 cm gap | 433 / 624 | 465 / 624 |
| Entire-road footprints over 50 cm gap | 108 | 87 |
| Worst entire-road gap | 87.21 cm | 84.04 cm |

The occasional small frontage gap includes surface joins at the road edges.
Smooth transitions still cross fractional block heights. This improves the
principal building streets, NOT arbitrary slopes or every road in a world.
Intentional floating construction remains permitted everywhere.

The real placement handler places one ordinary brick, leaves the lower cell
empty, leaves terrain density unchanged and preserves exact floating face
adjacency. Terrain has the existing binary roundtrip; no new save format.
The runner checks the 291 original Wild_Hills files before/after; they are
unchanged. The temporary slot never loads or writes that save.

`baseline.png`, `proposed.png` and `proposed_overview.png` are inspected actual
1920×1080 engine renders, not generated artwork. The close view visibly removes
the unsupported gap without adding blocks below the brick. The overview retains
the surrounding wooded landscape rather than flattening the entire rectangle.
Roadside banks are more pronounced locally; human appearance approval is still
required. Screenshot/readback frame counters are not performance measurements.

## Verification and retained failures

Commands:

```
python tools/run_godot_check.py road_frontage_plan --headless --timeout 90 --require "ROAD_FRONTAGE_PLAN failures=0"
python tools/review_road_grades.py --check
python tools/review_road_grades.py
```

Native debug and release DLLs are rebuilt. Scoped checks cover native plan
determinism, unchanged default planning, rejected malformed/mixed flags, shared
cubic height/tangent continuity, original plate encoding, frontage constraints,
master baking, binary terrain restoration and integrated collision/placement.
Existing paving and seven-seed lot-planning regressions pass. See `validation.json`
for the exact run records and library hashes. Both comparison modes regenerate
within one process; the preview world defers cursor capture until ready.

Failed local checks are retained, not counted as passes:

- `reports/checks/20261025T163149687652Z`: initial review script type-inference error.
- `20261025T163227710086Z` through `20261025T163830655752Z`: infeasible layout
  experiments, including 128 m roads and an eight-house recipe. The search did
  not relax earthwork limits to accept them. The review is explicitly reduced
  to four unchanged houses; an improved eight-house generator is NOT complete.
- `reports/road_frontage_review/1d801deb8f714f84b7b3c66590bee930`: review variable
  collided with Node's `ready` signal; renamed before the passing checks.
- `reports/road_frontage_review/0cd1636329804f2dac149ca62696af0c`: fixture disabled
  player physics before floor initialization; startup sequencing corrected.
- `reports/checks/20261025T165139098574Z`: added test guessed the plate's packed
  word incorrectly. It now asks the existing native encoder; production plate
  geometry and encoding were not changed to satisfy the test.

## Rejected direction and remaining gates

Human review rejected this as the requested solution. It is not awaiting approval
for default integration; reconsider it only as a separately requested local road
type. The remaining historical qualification limits are recorded below.
Four-house evidence does not qualify the eight-house market, larger towns or
regional highways. Return to co-planning complete settlements after this review;
retain cut/fill budgets and move/reorient/divide unsuitable layouts rather than
flattening a whole town. Water/POI reservations, turns/crossings, wider objects,
all entrances and roadside transitions need complete multi-seed qualification.
The isolated comparison is not connected into the complete generated regional
network and does not claim reservation-aware final site selection.

Connected on-foot/vehicle traversal, full-world fresh-process save/reload,
multi-seed coverage, cache identity/version migration and measured performance
remain required before a Create World option/default is added. This preview
does not silently solve those gates. No automatic-foundation follow-up is planned.
