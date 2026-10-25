# Building reviews — A2 roof pending, Shop B approved

## A0 roof revision A2 — awaiting approval

Run `python tools/review_modular_buildings.py --roof` for the dedicated comparison:
unchanged A0 on the left, new A2 on the right, with matching cameras and signs.
Exterior, Interior and Detail show the continuous thin roof and underside.
`Remove ONE roof block` demonstrates a real local hole; `Restore that block`
restores it. The original remains untouched in either case.

A2 retains the original footprint, rooms, stairs, doors, windows, furniture and
storage. Only the roof assembly changes: thin native slope/ridge cells with
separate grid-contained seam infill, and continuous timber gable backing above
the eaves instead of the old brick/wood staircase edge. No A1 porch is reused.
`roof_recipe.gd` is offline authoring for `baked/cottage_roof_a2.tres`; runtime
loads the baked native resource. A2 is not a production prefab or generation
default and does not alter existing saves. Approval of B1 does not approve A2.

Evidence: `../../docs/evidence/cottage_roof_a2/README.md`.

## Accepted designs and historical comparison

Run `python tools/review_modular_buildings.py` from the TerraForest directory.
It opens one signed, walkable Godot scene, starting at the shops. A0 is the original
cottage, B0 the original shop, B1 the approved additional shop. Rejected A1 is not
placed. WASD/mouse move/look, Shift runs, Space jumps, E opens/closes a nearby door.
1 visits the cottage, 2 the shops, 3 opens the overview, F toggles flight (Space up,
Ctrl down). Esc opens/closes navigation and releases/recaptures the pointer.
Nothing is saved to the player's world. No additional CMD launcher is installed.

Use `python tools/review_modular_buildings.py --comparison` for the historical
side-by-side viewer and 45-second guided tour. The **original is on the left**,
the **reviewed alternative on the right**, labeled with its decision. Choose
Cottage A or Village Shop B, then Exterior, Interior or Detail. Selecting a view
stops the tour. The removal button removes one native arch block in the proposal;
restore it or change views to reset that demonstration. Doors can be opened and
closed. Escape/Close exits; nothing is saved to the player's world.

## Decisions — 2026-10-25

- **Cottage A R1: rejected.** The existing furnished brick cottage, with a multi-block timber
  porch arch and roof, supported side pedestals, flush timber gables, peaked ridge
  and a thin timber ceiling. The center stair route remains open.
- **Village Shop B R1: approved as an addition only.** The existing village general store, with a four-sided
  hipped roof, individual hip-corner/ridge blocks, a thin ceiling and a segmented
  arch into the rear stores. Counters, doors, windows and storage remain in place.

Both retain independent native grid-cell ownership. Rendering can merge cells;
the underlying structures remain individually editable/destructible. The porch
and stores arch use two quarter-arch blocks and a separate top-panel block, plus
separate supporting building parts. Neither is a complete architectural mesh.

`baked/*.tres` are native prefab resources, not live runtime recipe generation.
`recipes.gd` retains reproducible offline authoring; the test checks the baked
records and attached objects against those recipes. The approved B1 has an exact
production copy at `addons/structures/prefabs/village_shop_hipped_r1.tres`, appended
to the construction palette. Original recipes and existing saves remain unchanged.
The historical review assets and `reviews/*` remain excluded from game exports.

## Acceptance

B1 is the only approved addition; A1 must not enter the production catalogue.
The old cottage roof is not visually accepted either: the next roof proposal must
show continuous-looking slopes and clean thin edges, not diagonal block steps.
The separate A2 review now supplies native thin 45-degree roof assemblies; it is
not yet approved. Arbitrary/shallow pitches remain outside this revision.
Approval of B1 does not authorize replacement of an original or automatic adoption
by generation. Terrain fitting and integrated-world checks precede that step.

Evidence and known limitations are recorded in
`../../docs/evidence/modular_buildings_r1/README.md`. This isolated comparison is
not a replacement for a playable-world terrain, NPC or performance review. Updated
signed-scene and palette evidence is in `../../docs/evidence/approved_shop_review/README.md`.

Reproduce the graphical check:

```text
python tools/run_godot_check.py modular_building_walkaround --timeout 180 --require "MODULAR_BUILDING_WALKAROUND checks=" -- --review-output=res://reports/modular_building_walkaround/approved
python tools/run_godot_check.py approved_shop_addition --headless --timeout 120 --require "APPROVED_SHOP_ADDITION checks="
python tools/run_godot_check.py modular_building_review --timeout 120 --require "MODULAR_BUILDING_REVIEW checks=" -- --review-output=res://reports/modular_building_review/recheck
python tools/run_godot_check.py modular_building_review --headless --timeout 60 --require "MODULAR_BUILDING_RESTORE checks=" -- --review-output=res://reports/modular_building_review/recheck --restore-review
```
