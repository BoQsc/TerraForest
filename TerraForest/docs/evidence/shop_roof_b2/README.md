# B0 thin-roof proposal B2 — 2026-10-25

The user asked to try fixing B0's roof using the approved A2 approach, not redesign
the shop. This is a **review-only B2 proposal**, not approved for replacement.
B0 and the separately approved hipped-roof B1 remain unchanged.

## Scope

- A separate baked native prefab contains 1,028 independently owned grid cells.
- Reuses the existing thin slope, ridge and seam-infill shapes (15–18); no new
  native geometry, runtime roof generation, house-sized mesh or per-block nodes.
- Replaces the raised solid ridge and stepped roof underside with a continuous
  thin 45-degree shell. Upper gable backing becomes timber, following A2.
- Adds one-cell front/back roof overhangs. The above-ground envelope changes;
  foundation samples are identical in all four rotations.
- Keeps walls below eaves, floor, partition, steps, doors, windows, counters,
  shelving and storage unchanged. Only four small overhang seam cells are added
  below roof level, outside those original walls.

## Verification and visual review

| Check | Result | Evidence |
| --- | --- | --- |
| Graphical bake/comparison and native traversal | 26 checks, zero failures | `comparison/` |
| Fresh-process exact compound restore | 3 checks, zero failures | `restore/` |
| Existing approved A2 comparison regression | 16 checks, zero failures | `a2_regression/` |

The comparison verifies unchanged sub-roof cells and attached objects, exact
offline-recipe reproduction, unchanged foundations, approved B1 identity,
independent roof-block removal/restoration and native movement up the steps,
through each door/interior aisle and back out. The separate process restores
exact block/model storage bytes. The sign helper remains compatible with A2.

Inspected all four actual Godot screenshots in `images/`: the new ridge has no
raised box, roof edges are thin and continuous, the underside has no diagonal
steps, and removal creates a local hole in only B2. The timber upper gable and
longer front/back overhangs are visible changes for the user to review.
These are engine renders, not image-generated mockups. The original is on the left.

Production cottage/shop resources, generation recipes and native libraries are
unchanged. Relevant source/resource hashes and run results are in `manifest.json`.
Review assets remain excluded from exports. No user saves are read or written.

## Pending

- Explicit user approval of B2 before replacing B0 or adopting it in generation.
- The expanded roof envelope needs generated-site fit, street access and
  populated-world performance checks before adoption; isolated review traversal
  does not establish those results.
- The preceding B1 generation-addition request remains open. Work switched to
  this B0 roof trial before generation recipes were edited; resume that separate
  integration after presenting this proposal. Do not treat B2 review as B1 adoption.

## Reproduce

```text
python tools/review_modular_buildings.py --shop-roof
python tools/run_godot_check.py shop_roof_review --timeout 120 --require "SHOP_ROOF_REVIEW checks=" -- --review-output=res://reports/shop_roof_review/recheck
python tools/run_godot_check.py shop_roof_review --headless --timeout 60 --require "SHOP_ROOF_RESTORE checks=" -- --restore-review --review-output=res://reports/shop_roof_review/recheck
```

Add `--bake-roof` only to explicitly regenerate the baked review asset.
