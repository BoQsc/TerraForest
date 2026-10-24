# Hammer and shovel, 2026-10-24

Two editable Blender R11 sources now provide Idle, Walk, Run, Jump and Swing
actions for the existing repair hammer (item 3) and new shovel (item 5). The
original pickaxe/hatchet assets, item IDs, runtime body and saved loadouts keep
their identities. Shovel crafting costs two wood and two metal; it has 200
durability and participates in inventory, storage, native world drops and saves.

## Current tool revision

The hammer has a dense rounded forged head with two flush faces and no conical
peen projecting toward the player. Its complete mesh has 10,544 triangles.
The shovel has a curved, solid blade and rear socket; its complete mesh has
17,096 triangles. The rectangular shoulder treads are removed. Both use embedded 1024px brushed-steel color, roughness and
normal maps, metallic steel, smooth head normals and machined edge materials.
Held tools, static inventory tiles and baked dropped meshes share the materials.

The shovel's **cutting end points forward while the concave inside is visible
to the player**. The blade leads the shaft by 25 degrees. The Blender rebuild
checks the scoop opening against the actual ready-view eye position; the
current dot product toward the eye is +0.359. This is a geometry direction
check, not a substitute for the user's visual acceptance.

Earlier low-detail heads and the hammer peen were rejected by the user. An
early attempted shovel rotation was visually canceled by changing its curvature
too. The subsequent rounded-back view was also rejected: the user's intended
view is the inside of the scoop, with the cutting end leading forward. These
requirements must not be represented as approved by passing engineering checks.
The user requested committing the current revision after these changes,
including removal of the rectangular shoulder treads. Engineering results
remain separate from broader world-quality and performance acceptance.

## Verification

The current source checks pass 85 assertions: 23 world/tool checks, 27 animation
timing checks, 13 loadout checks, 16 drop checks and 6 existing icon/UI checks.
`verification.json` records the checked asset hashes. The adjacent stills and
MP4s show the current revision; the adjacent logs retain final check results.

`tests/attack_animation_timing.gd` checks visible authored contact, recovery,
playback speed and cancellation. Hammer contact is frame 28/60; shovel contact
is frame 34/60. The assembly tool retains its existing procedural behavior.

`tests/hammer_shovel.gd` runs a temporary, rendered gameplay world. It exercises
real crafting; old/new inventory restore; dropping, compound pickup-provider
restore and recollection without losing wear; a real block repair at the hammer
contact; actual mouse-driven native terrain excavation/rewards at shovel
contact; and the imported dense meshes/PBR texture bindings. No user world is
written. `tests/gameplay_loadout.gd` and `tests/inventory_drop.gd` cover existing
starter contents, no refill on restore, ordinary supply drops and rejection.

Initial harness attempts are not acceptance evidence: headless input could not
capture the mouse; restoring raw snapshots for every world provider hit the
water preparer's different input contract; and waiting a fixed four physics
frames sometimes preceded publication of the fixture block's collider. The
current rendered check restores only inventory/pickup providers and waits for
the real collider. Two older regression fixtures lacked the current terrain
restore context; minimal SnapshotTerrain fixtures now supply it. A preview
script enum typo was corrected to the existing project's REFLECTION_SOURCE_SKY.

Rebuild and runtime integration are documented in
`addons/characters/authoring/Human.hammer_shovel.README.md`. Logs, current camera
stills, full-speed/half-speed videos and import/source provenance are retained
under `reports/hammer_shovel*`, `reports/author_hammer.log`,
`reports/author_shovel.log` and `reports/item_icon_refresh/`. This evidence
qualifies these tools and their interactions, not large-world performance,
navigation or unrelated ongoing boulder work.
