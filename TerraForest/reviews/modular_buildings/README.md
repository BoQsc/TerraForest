# Building proposals R1 — review only

Run `python tools/review_modular_buildings.py` from the TerraForest directory.
It opens one side-by-side Godot window and starts a 45-second guided tour. No new
CMD launcher, game default, save migration or world replacement is installed.

The **existing building is on the left**, the **proposal on the right**. Choose
Cottage A or Village Shop B, then Exterior, Interior or Detail. Selecting a view
stops the tour. The removal button removes one native arch block in the proposal;
restore it or change views to reset that demonstration. Doors can be opened and
closed. Escape/Close exits; nothing is saved to the player's world.

## Proposals

- **Cottage A R1:** the existing furnished brick cottage, with a multi-block timber
  porch arch and roof, supported side pedestals, flush timber gables, peaked ridge
  and a thin timber ceiling. The center stair route remains open.
- **Village Shop B R1:** the existing village general store, with a four-sided
  hipped roof, individual hip-corner/ridge blocks, a thin ceiling and a segmented
  arch into the rear stores. Counters, doors, windows and storage remain in place.

Both retain independent native grid-cell ownership. Rendering can merge cells;
the underlying structures remain individually editable/destructible. The porch
and stores arch use two quarter-arch blocks and a separate top-panel block, plus
separate supporting building parts. Neither is a complete architectural mesh.

`baked/*.tres` are native prefab resources, not live runtime recipe generation.
`recipes.gd` retains reproducible offline authoring; the test checks the baked
records and attached objects against those recipes. No production catalogue
references these alternatives, and `reviews/*` is excluded from game exports.

## Acceptance

Both designs are **unapproved**. Approval of one is not approval of the other.
An approval applies to that named R1 proposal, not to every use of the new shapes.
Terrain fitting and integrated-world checks follow approval before adoption.

Evidence and known limitations are recorded in
`../../docs/evidence/modular_buildings_r1/README.md`. This isolated comparison is
not a replacement for a playable-world terrain, NPC or performance review.

Reproduce the graphical check:

```text
python tools/run_godot_check.py modular_building_review --timeout 120 --require "MODULAR_BUILDING_REVIEW checks=" -- --review-output=res://reports/modular_building_review/recheck
python tools/run_godot_check.py modular_building_review --headless --timeout 60 --require "MODULAR_BUILDING_RESTORE checks=" -- --review-output=res://reports/modular_building_review/recheck --restore-review
```
