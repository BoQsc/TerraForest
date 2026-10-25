# Connected road grid preference — 2026-10-25

This is an implemented generation improvement, not universal acceptance. The
previous audit at `../grid_network_audit/` remains the before evidence. Existing
Wild_Hills and the user's saved failing GridPreference world are not regenerated.

## Implementation

- Native graph stations at most 3 m apart share source-junction heights. Joint
  projected height/tangent constraints target integer height plus 4 cm without
  moving the building lattice or invoking placement-triggered terrain changes.
- Source displacement remains bounded at 55 cm; final cubic grade is analytically
  bounded at 20% and curvature at 0.04/m. Full-width earthwork surveys at no more
  than 0.5 m spacing retain 3 m cut / 2 m fill, with a 6 cm fitting reserve.
- Fixed lots, entrances, integer flat streets and crossing neighborhoods stay
  protected. Matching soil beds and native navigation use the fitted geometry.
  Trusted house origins and sidewalk plate records compare exactly across seeds.
- An infeasible adjustable regional corridor returns an explicit location. The
  production planner excludes it and retries native routing, at most four times.
  No old-road fallback is used on exhaustion. The preview/cache and final bake
  consume the same plan. Work is generation-time native CPU work, not per-frame
  GDScript or GPU readback; binary plans are cached by recipe and DLL identity.
- New default-on road settings encode road_grid=2 as 32-byte recipe v3. Old v1/v2
  bytes retain their algorithms. The existing terrain preference is unchanged and
  separately toggleable. Mining, building freedom and targeting are unchanged.

## Whole-network screening

An unfit footprint cannot satisfy both gap <=10 cm and burial <=25 cm with *any*
integer block base. These are diagnostic thresholds, not new placement restrictions.
The independent audit samples nine points per one-metre footprint. It is analytic
road-profile coverage, not physics verification of every shoulder or intersection.

| Seed | Original coverage | Connected coverage | Comparison |
|---|---:|---:|---|
| 1703 | 1,136 / 2,037 unfit | 646 / 2,037 unfit | Identical coordinates; previous normalizer was 1,009 / 2,037 |
| 42 | 688 / 1,386 unfit | 470 / 1,386 unfit | Identical coordinates |
| 9137 | 973 / 1,874 unfit | 634 / 2,009 unfit | New route after one exclusion; freshly sampled corridor |

For 1703, regional failures fall 782 -> 406 versus the previous normalizer, but
settlement failures rise 227 -> 240. Both improve versus unmodified roads
(871 regional / 265 settlement). This local regression is retained, not hidden by
the network total. For 9137, only 1,033 old coordinates still lie on the new roads;
246 failures there are **not** a comparable whole-network count. Fresh coverage
is included so rerouting cannot manufacture success by dropping old samples.

Uncached full production planning in the final run took approximately 0.94 s, 1.03 s
and 1.10 s for the three seeds on the current machine; this is neither a general
hardware benchmark nor the total generation/baking time. Cache hits were measured
separately during development, around 46–59 ms before the final smoothness change.

## Engineering and visual evidence

`network.json` contains deterministic multi-seed planning, preserved building/plate
records, rerouting, exact cubic grade/curvature and independent footprint counts.
`native_release.json` includes malformed-input checks, shared junctions, tangent
continuity, and a freshly meshed physics corridor with 0.25 m ray spacing in three
lanes. `recipe_release.json` verifies old/new binary identities and malformed data.
`generation.json`, `contact.json` and `review_run.json` cover the final generated
world and actual collision at the old town road, old natural ground and the user's
newly reported regional-road cell. Automatic review loads read-only and hashes the
source/review saves. Human visual acceptance remains pending.

Final graphical review world: `GridPreference_1703_2756a200`, seed 1703, terrain
23, road preference 2. All 44 sampled footprints meet the diagnostic contact limits.
At the user's reported cell (1076,47,838), nine actual collision samples measure
47.1217–47.2249 m: **22.49 cm maximum burial, zero gap**, versus the saved failure's
42.30 cm burial. The cube's integer base remains 47. No supports or offsets were
added. Images `reported_road.png`, `road.png` and `terrain.png` were inspected:
the local blocks meet the surface without visible air gaps, and approved building
and plate geometry remains present. This does not certify the broader network.
The standalone 1,209-ray collision test has no misses, 9.1 mm maximum height error
and 3.9 mm maximum join-step error relative to the designed smooth profile.

Interactive review starts at the reported regional road. F6 visits the old town
road, F7 the old natural-terrain case, and F8 returns to the reported road.

Final checks: connected native and three-seed planning; legacy normalization;
world recipe native/debug/release and UI planning; world browser; 31 integrated
generation checks; 44-footprint graphical review; packaged export/startup with all
14 native libraries. Export still reports pre-existing duplicate UIDs in retained
rejected-ramp snapshots under ignored reports; no export or script errors occurred.
The final bounds-validation hardening leaves the measured generated geometry
unchanged; the final DLLs repeat native physics and read-only graphical checks.

An earlier candidate passed contact checks but permitted curvature up to 0.20/m;
inspection found overly sharp transitions. It was not shipped. The final solver
constrains cubic endpoint curvature directly, rather than relying on a discrete
height-difference proxy. Initial station-only earthwork checks also missed an
intermediate cut; full-width final surveys and reserved fitting margin resolve
that. Seed 9137 cannot fit its original corridor and exercises actual rerouting.
The first isolated-release test harness omitted extension loading and timed out;
explicit loading and persisted release-test results correct the harness.

## Still incomplete

646 failing 1703 footprints are not acceptable as a claim of perfect roads.
Smooth elevation transitions, protected settlement approaches and arbitrary
terrain/block footprints still need improvement. Offroad trails retain their
existing grade planning. Broader shoulders, crossings (including collinear
overlaps), sustained driving and lower-end performance remain unqualified.
Further settlement/layout redesign still requires the user's approval. No
continuous roadside meshes or support mounds are introduced. The next iteration
must reduce those failures without hiding them behind greater burial, changing
the grid, or regressing the approved buildings and plates.
