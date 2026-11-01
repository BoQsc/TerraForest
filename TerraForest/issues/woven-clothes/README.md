# Visible woven clothing

- Status: Implemented / source and normal-world checks pass.
- Updated: 2026-11-01. Fix/build: woven woodland revision 1; see focused Git history.
- User review: Not reviewed.
- Symptom: Head, Body and Feet accepted the three woven items without changing
  the character's 3D outfit; inventory silhouettes were generic folded boxes.

## Images

![Woven outfit in three directions](images/fit-idle.png)

Revision 1, Godot 4.7.2 Forward+, 1600×1050, front/side/back sampled R11 Idle.
Original hood, vest and footwraps share the existing animated skeleton. The old
carry harness is hidden with the replaced field vest. Assistant visually reviewed.

![Actual equipment screen with baked garment icons](images/character-equipped.png)

Source HUD, 1920×1080, same actual garment meshes in the portrait and icon bake.
All three were crafted from nine plant fibres and equipped through ordinary slots.
The navigation shell is concurrent work, preserved by this clothing change.

![Restored outfit in a generated world](images/world-restored.png)

Dedicated `Woven_` fixture, generator 1 / seed 1703, ordinary world entry and a
fresh process after saving. Existing third-person camera, no user save edited.

![Inherited crouch defect before the clothing pack](images/base-crouch.png)

Base R11 outfit, same stage and mid-crouch pose. The skin patches at the knees
predate these garments. This pack does not replace the trousers or fix that defect.

![Same crouch pose wearing the new garments](images/woven-crouch.png)

Same camera and pose. Hood, vest and footwraps remain attached; inherited knee
clipping remains visible. This image is not acceptance of the underlying trousers.

![Rejected first fit](images/rejected-first-fit.png)

First fit: inherited carry straps protruded through the vest. Run samples also
exposed skin through the first sole. Replaced by scoped harness visibility and
larger closed soles. Earlier evidence is preserved, not represented as accepted.

## Changes and verification

- Independently authored geometry, weave textures and ten-bone weights. Original
  asset/data dedication CC0-1.0; generator/adapter/test code 0BSD. Exact paths,
  provenance and hashes: [pack](../../addons/characters/wearables/woven/README.md).
- One event-driven adapter for both views; cached meshes, no inventory polling,
  no runtime mesh authoring, no additional movement/animation owner. Remove
  restores original clothing, harness and hair visibility. Hood is hidden in FP.
- Real paid recipes and stable IDs 301–303, no inventory schema or gameplay bonus
  change. Actual garment icon tiles and compressed normalized ground models.
- 49 focused source assertions pass: geometry/weights, normalized ground meshes, paid recipes, wrong and
  stale drags, equip/remove, restoration of both storage components, FP/3P
  visibility, cached portrait rendering and six front/side/back pose samples.
- Existing inventory navigation regression: 24 assertions pass.
- Normal generated-world craft/equip/save: 15 assertions pass. Fresh process
  restoration: 8 assertions pass, including the production player-view binding.
- Offline credits freshness and item-icon dependency freshness are checked.
- Exact commands, source reports, hashes and retained failures: [evidence.json](evidence.json).

## Remaining / resume here

- User visual approval is pending. Review idle, walk/run, crouch, pickaxe and punch
  images before requesting a broader animation sweep or changing the silhouette.
- Inherited trouser skin clipping remains. Return on a body/trouser fitting task;
  closure requires the same base-versus-new crouch comparison plus movement poses.
- Animation review is sampled, not all-frame or all-clip certification. Additional
  character proportions require a new fit and weight pass.
- Main installed executable/package validation is outside this source asset-pack
  delivery and remains unreviewed. Return on the next combined build and run the
  same equip/save/reopen checks against the exported package. Concurrent navigation
  edits were exercised together but are not folded into the clothing commit.

## Reproduce / history

From TerraForest: `python tools/check_woven_clothes.py` for source/HUD renders;
`python tools/check_woven_clothes.py --world` for an exclusively owned, uniquely
named generated fixture followed by a second process. Neither targets user slots.

Early source fixture rejected quantized weight sums with an overly strict float
comparison and produced unused black viewports. The check now uses the stored
weight precision bound and explicitly renders the review viewport. The first world
fixture failed the no-pointer-capture assertion because the browser reset the
offscreen flag; the fixture now reapplies that flag as the world scene is added,
matching the existing offscreen navigation harness. Those failed logs are retained.
