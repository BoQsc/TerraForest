# Firearms, explosions and optional structural integrity

Source verification: 2026-11-01. The feature is implemented and checked; the
combined installed-game export is coordinated separately. See the
[combat issue](../issues/explosive-combat/README.md) for current verification.

## Play

Craft a **Carbine**, **Carbine cartridges**, and **Explosive barrel** in the
inventory, or obtain them from **Esc → Dev Bag**. These are original game-balance
recipes. The existing starter loadout and saved inventories are preserved.

- Carbine: left mouse fires, right mouse aims, R reloads a 30-round magazine.
- Barrel: equip it, then right-click nearby clear ground to place one. Gunfire or
  melee damage ignites it. Nearby barrels can chain-react.
- Esc → Player → **Structural integrity and collapse** enables the optional
  support simulation. It defaults off and is saved with each world. Blast damage
  and flying debris still work while the integrity option is off.

The existing `Human.r11.glb` contains the carbine and all ten first-person clips:
idle, walk, run, jump, aim, aimed fire, hip fire, reload, equip and holster.
Third-person rifle locomotion, aim, fire and reload clips are also reused.
No external gun or animation pack was imported.

## Runtime ownership

`combat_world.gd` is a bounded event adapter. Native inventory owns carried items;
`NativeCombatState` owns magazine, integrity preference and queued destruction
snapshot validation. Reload consumes cartridges only when the authored animation
finishes. Switching item, opening a menu, losing focus, or changing world cancels
the reload without consuming ammunition. Magazine state is shared by the player's
single carbine weapon type; individual carried carbines do not have separate
magazines.

At most 64 travelling projectiles are resident. Each advances with gravity and a
swept segment query against native block/scene collision and the existing live
zombie anatomical pick. Unavailable collision ends the projectile rather than
allowing it through unloaded geometry. Hits use the existing `firearm` reaction,
limb damage and ragdoll path. World interactions are suspended by gameplay UI.

Explosive barrels are ordinary persisted native model placements with stable
asset key `combat/explosive_barrel/v1`; partial damage uses native world durability.
Placement is limited to 256 barrels and rejects overlaps or the player's body.
An ignited barrel remains represented by its saved damage until it can detonate.

The 3.5 m terrain crater uses `terrain.edit` with the same subtractive density
brush, edit admission, water checks, publication, vegetation updates, navigation
invalidation and save path as mining. A narrowly scoped environmental edit token
avoids awarding mining resources or blocking an explosion on inventory capacity.
It does not replace the terrain with a heightmap cut or a visual decal.

Within 5 m, native code selects building cells inside the blast sphere. The adapter
applies distance-dependent damage to existing per-cell durability, 24 candidates
per tick. Destroyed cells are removed from the native block store. Permanent
geometry edits are saved; undo histories cannot resurrect a destroyed object.
Queued destruction retains its exact cursor in the combat snapshot so a save in
the middle of a blast can resume remaining cells without damaging processed cells
again. Pending ignited chain barrels resume through their durability records.

Each removed cell can become a shape-matched convex rigid body with an outward
impulse and spin. Up to 96 debris bodies live for eight seconds, collide with the
static world, and freeze during pause. These are temporary visual debris, not
saved recoverable building pieces or new player platforms. Their material colors
follow the four structural materials; detailed surface appearances are not copied.

## Integrity rule and limits

Building edits and published terrain edits schedule a bounded 32 × 32 × 32 cell
neighborhood. Terrain support samples are requested asynchronously in batches of
128, with terrain epoch/revision and block revision checks. Native code propagates
support through six face-adjacent occupied cells. Brick, wood, concrete and metal
have different strength and lateral span costs; vertical load also spends support.
Disconnected pieces and overlong cantilevers collapse in batches of 12 cells.

This is a voxel gameplay rule, not an engineering stress or fracture simulation.
Shapes use their occupied lattice cell for connectivity. Boundary cells remain
conservatively anchored because the continuation outside the checked neighborhood
is unknown. Unloaded or changing data defers the check. There is no scan of all
buildings every frame, and this implementation does not certify global collapse
of arbitrarily large buildings spanning multiple resident neighborhoods.

Terrain itself remains a volumetric field: explosions and mining remove density.
The optional support rule applies to authored building blocks, not a new rigid-body
simulation of terrain islands. Existing static furniture models are not converted
into voxel buildings by this feature.

## Verification and packaging

- `tests/combat_state.gd`: native magazine/validation, queued destruction restore,
  support/cantilever cases and actual authored animation completion/cancellation.
- `tests/combat_world.gd` / `tools/check_combat.py`: private disposable saved world;
  reload, projectile, zombie response, barrel placement/chain reaction, crater,
  debris pause and integrity toggle, followed by a fresh-process reopen.
- Keep the existing melee timing and durability regressions as compatibility gates.

The final source journey passes 31 creation and 11 fresh-process restore checks
in `reports/combat_world/20261101T181508831902Z`. The reopened world retains exact
ammunition, barrel damage, crater density, destroyed cells, the integrity setting
and an interrupted blast cursor. Its completed prefix is not damaged again.
The native/animation suite passes 66, isolated debug/release native suites pass
46 each, melee timing/durability pass 27/21, and quests pass 53 per native variant.
The issue tracker retains exact report paths, native hashes, failed fixture runs,
and reviewed images. The HUD overlap/clipping and blast damage label are corrected.
No offscreen test captures the desktop pointer.

The shared native libraries also contain the concurrent trader inventory work.
Their artifact commit and final packaged verification belong to the coordinated
combined export after both source commits. That export is not claimed by the
source checks. User visual review remains separate from engineering verification.

Original code is 0BSD. Original procedural barrel, icons and synthesized sound
data are CC0-1.0; inherited rifle and character provenance is preserved. Exact
paths and origins are in `addons/player_runtime/COMBAT_PROVENANCE.txt`.
