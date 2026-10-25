# Bidirectional terrain and road grid preference

2026-10-25. Engineering baseline; human visual acceptance remains pending.
This is not a claim of perfect contact at every cell in a continuous landscape.

## Implementation

- New native generator IDs 22/23 preserve saved profiles 20/21 unchanged. An
  existing 65 x 65 byte eligibility field weights wider smooth height levels.
  A second smooth correction raises small remaining depressions as well as
  lowering high spots toward integer height plus 8 cm. Mountains, protected
  shores and unsuitable slopes retain their exclusions/fades.
- Separate default-on Terrain and Roads creation options. The road bit lives
  in the 32-byte version-two recipe; 28-byte version-one worlds do not opt in.
  Native generator identity and recipe bytes participate in plan/cache identity.
- Native road fitting anchors joins and protected entrance/crossing intervals,
  limits height shift to 55 cm, grade to 20%, added grade to 10%, and added
  curvature to 0.04/m. Full-width 0.5 m surveys retain the 3 m cut / 2 m fill
  budgets. Unsupported or over-budget sections retain their original grade.
- With Roads enabled, plate-bed cuts stop 3 cm below the street rather than
  10 cm below it. All trusted plate cells, shapes and positions remain unchanged.
  This avoids an incidental depression spreading into the road-edge mesh.
- Placement stays on the integer lattice. The separate session preference cannot
  replace a gap of 10 cm or less with deeper burial, or bury a cube more than
  60 cm. This safety ceiling is not an accepted visual-quality target. No terrain
  edits, foundation supports or block offsets occur when placing a block.
- New-profile cellar lots reject road-support overlap across their upper house
  footprint, not only the smaller basement foundation probes. House assets do
  not change.

## Evidence and limits

`contact.json` measures actual physics collision at 42 old road footprints and
one old natural-terrain footprint in a separately generated seed-1703 world.
`road.png` and `terrain.png` are engine renders of ordinary placed blocks, not
mockups. The review launcher fails its automatic run if any sampled footprint
exceeds the provisional 10 cm gap / 25 cm burial limits. These limits remain
separate from user visual acceptance. Original Wild_Hills and the automatic
review save are hashed before/after to detect modifications.

Latest slot: `GridPreference_1703_f3de49d9`. All 43 sampled footprints meet the
provisional limits: road gap 0–4.50 cm, mean 1.95 cm, zero road burial; natural
gap zero, burial 8.01 cm. Both images were inspected. Road center blocks are no
longer visibly suspended high above the road, and the natural cube remains
mostly exposed. That observation does not constitute the user's approval.
`generation_run.json` and `review_run.json` retain exact commands, revisions and
outcomes; `generation.json` identifies the isolated world and production report.

`embedding.json` samples 5,269 gentle, low-altitude natural footprints across
seeds 0, 42, 1703 and 2147483647. Both sides use the same bounded targeting rule:
2,693 -> 3,441 meet both provisional limits; gaps over 10 cm fall from 1,459 to
1,110. No tested cube exceeds 60 cm burial. Maximum sampled landscape displacement
is 50.41 cm. These are analytic base-height samples, not rendered full-world
collision coverage. The remaining 1,110 gaps are an open failure of universal fit,
not permission to accept them. Do not describe this survey as all terrain passing.

`checks.json` retains three-seed road planning measurements and limits. The
complete generation check validates generation, live loading, approved building
cells, saving, selector return and restoration. Native debug/release checks and
pack startup are engineering gates, not substitutes for terrain-quality review.

Final verification: full generation 31/31; paving 85/85 (debug and release);
release native recipe 18/18; release cubic profiles, three-seed road normalization,
legacy buildable terrain, new bidirectional terrain, bounded placement, terrain
placement, browser and original road-trial checks pass. The exported pack starts
with its 14 external native libraries. Logs retained here include the three final
release checks. Five superseded preview worlds are recoverably archived under
the game's `review_archive/grid_preference_20261025_rejected`, not deleted.

## Rejected iterations

- The original generation-only correction retained an 86.48 cm worst road gap.
- `rejected_contact_first/`: lowering blocks aggressively removed gaps by burying
  road cubes up to 99.78 cm and the natural-terrain cube by 100.60 cm. Explicitly
  rejected by the user. That downward-snap algorithm is removed.
- `rejected_road_edge/contact.json`: bidirectional generation fixed the natural
  case (zero gap, 8.01 cm burial), but 14 road-edge footprints still had 12.93 cm
  gaps. This failed the quality gate and prompted the shallower plate-bed fix.
- Early recipe tests assumed a fixed 28-byte payload; updated to validate both
  versions. Early test scripts used unsupported PackedFloat32Array min/max and
  stale browser option indices; fixed before passing reruns.
- A full-generation run exposed road fill inside a cellar house's upper footprint.
  A universal road/house exclusion then prevented all three tested seeds fitting;
  rejected in favor of the scoped cellar exclusion described above. Failed logs
  remain under reports/checks (190148196881Z and 190638638448Z on 2026-10-25).

## Remaining acceptance work

Keep this requirement open: sampled natural transitions still fail; all road
transitions, edited/player-placed terrain, entrances and populated on-foot/vehicle
traversal need broader rendered evidence. Smooth continuous elevation changes
cannot simultaneously provide shallow contact for every fixed-height cube at
every possible position. Do not hide this by deep burial, shifting the lattice,
automatic supports or silently relaxing thresholds. Return to the failed regions
after this old-case playtest and qualify a bounded transition policy with the user.

Reproduce with `tools/run_godot_check.py world_recipe_generation --timeout 600
--require "WORLD_RECIPE_GENERATION checks=" -- --grid-review`, then
`python tools/review_grid_preference.py`. Use `--play` for the ordinary interactive
review: F6 returns to the old road location and F7 to the old natural location.
Only isolated GridPreference_1703 slots are accepted by this launcher.
