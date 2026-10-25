# Submergence preference and gradual road cuts

2026-10-25. **Prototype only; human acceptance pending.** No normal gameplay,
world-selector or generation defaults changed. Wild_Hills was read through a
temporary read-only snapshot; all 291 source files matched their initial hashes.
No new UI label, supports, moved saved blocks, new house or sidewalk designs.

## Separate controls

- `NativeBlockWorld.placement_support(..., prefer_burial=false)` retains its
  previous behavior when omitted/false. The optional rule uses the existing nine
  rays, requires all nine contacts and a unit-cube footprint, and chooses a lower
  integer cell only if burial is at most 0.60 m and at most 1.5 times the upper
  cell's gap. At least 40 cm of the cube remains above the highest sampled ground.
- `demo/world.gd.prefer_block_burial` defaults false. The review explicitly enables
  it only for terrain-targeted cubes. Face placement never shifts off the targeted
  adjacent cell; its trial allowance matches the cube rule. Other shapes, thin
  plates and object placement remain unchanged. No additional support physics scan.
- `NativeRoadProfile.burial_trial` is independent of runtime placement. Its
  offline phase preference is smoothed over a 6 m neighborhood and tapered over
  up to 8 m at each existing segment end. Shape-preserving cubic cuts cannot
  raise the surface. Continuous polynomial extrema enforce <=18 cm cut, <=2.5
  percentage points added grade, <=0.01/m added curvature and <=16% total grade;
  original steeper roads stay unchanged. Existing junction heights/tangents and
  flat sections remain anchored. Monotone chains cannot reverse their grade.
- `road_grid_trial.gd.segments(source, true)` invokes this second experiment;
  its original one-argument behavior is unchanged. Production never calls it.

The native fit caps output at 64 intervals per profile, 32 constraint iterations,
and a bounded smoothing stencil. The adapter caps the complete output at 4,096
stamps. It currently subdivides too much for a production efficiency claim:
seed 1703 uses 316 -> 1,178 plan stamps, with 58 source segments changed and a
largest fitted cut of 12.61 cm. These are plan measurements, not a full-world bake.

## Same saved road, real collision and click handler

Seed 1703, generator 21. Segment (1003.667,35,1093) to (1018.333,36,1093).
Fourteen longitudinal grid positions by three lateral positions; nine rays per
one-metre footprint. Comparison uses actual loaded terrain and native collision,
not only the analytic centreline. Three temporary bricks use the real placement
handler. The fourth, pre-existing floating brick stays unchanged in all images.

| Mode | Mean gap | Worst gap | >50 cm gap | <=15 cm gap | Worst burial |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original | 31.11 cm | 86.48 cm | 13/42 | 19/42 | 19.60 cm |
| Prefer submergence | 8.36 cm | 42.73 cm | 0/42 | 33/42 | 59.26 cm |
| Also gently correct road | 8.62 cm | 43.24 cm | 0/42 | 33/42 | 57.52 cm |

The conservative correction is only 1.81 cm on this short road. Aggregate burial
falls from 6.525 to 6.343 m across the 42 footprints, while mean gap increases
slightly by 0.27 cm. This is a measured trade-off, not a universal improvement at
every cell. The main improvement is the targeting preference. Deep burial remains
plainly visible; do not call it slight embedding or a complete solution.

Images inspected at 1920x1080: `original.png`, `prefer_submergence.png`,
`gentle_correction.png`, `gentle_overview.png`. The road silhouette remains smooth
in these views, but the small grading difference is subtle. Original house,
plates, terrain/vegetation and saved brick remain. No claim about performance
follows from the HUD FPS or screenshots.

## Reproduce and engineering evidence

Close the normal game first, then run `python tools/check_road_burial_preview.py`.
The launcher requires Wild_Hills, hashes its files, runs native generation checks,
then opens one graphical read-only snapshot process for the three comparisons.
It saves images/measurements, shuts down without saving, and verifies the hashes.
This is an automated preview, not an installed playtest or Create World option.

Final integrated run: `reports/road_burial_trial/7f73afb42c3849648aa99bb094cf5668`.
Zero engine diagnostics, normal exit, 25.95 seconds including loading, edits and
screenshot waits. Tests also check adjacent partly buried walls and intentional
floating face placement. `contact.json` retains each footprint, not just averages.
`profile.json` retains 25 analytic slope/length cases, shared-join/flat-section
checks, the selected curve, plan counts and continuous-extrema certificates.
The fresh native density snapshot roundtrip passes; it is not a fresh-process
whole-world restore or a claim about other edited systems.

Default regressions: placement support `reports/checks/20261025T180453338247Z`,
original road-grid trial `.../20261025T180454547695Z`, world recipe
`.../20261025T180456220449Z`. Trusted paving is checked separately; its initial
runner invocation `.../20261025T180502906064Z` had the wrong completion marker,
despite all 83 checks passing and exit zero. The corrected invocation is retained
in `validation.json`.

Retained development results: `reports/checks/20261025T175831038927Z` failed
because the first cubic fit's overshoot limit disabled correction on this road.
Shape-preserving cuts fixed that; the first integrated run
`30f3f4cec7b04e49b84e9c741d7d6135` passed but corrected only 2.85 mm. Spatial
smoothing and anchoring every original join yielded the final modest 1.81 cm
correction. Neither passing run counts as visual approval.

## Required before a production generation option

Human approval of the burial trade-off; multi-seed, full-width earthworks and
entrance/plate/building-reservation checks; diagonal-road and coastal approaches;
on-foot/vehicle traversal; complete-world fresh-process restoration; bake-cost and
long-run runtime measurements. Only then expose a separate opt-in recipe field,
UI, binary roundtrip and cache identity. Do not mutate existing saves or use this
preview's in-memory grading to migrate worlds. No automatic foundation fallback.
