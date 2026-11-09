# Firearms, explosions and optional structural integrity

2026-11-09 performance update: destructive edits now use revision-checked native
batches (24 blast candidates / 12 collapse cells per tick). The 704 exact debris
collision poses are baked into a 56 KB binary resource instead of decomposing
meshes during explosions. Rejected edits retain cursor and durability; visual
geometry, physics properties and limits are preserved. [Measurements, regression
evidence and remaining dense-combat work](../issues/runtime-performance/foundation-2026-11-09.md).

Source and packaged verification: 2026-11-01. The feature is implemented, included
in the combined game package, and checked through the existing game executable. See the
[combat issue](../issues/explosive-combat/README.md) for current verification.

## Play

Craft a **Carbine**, **Ranger assault rifle**, matching cartridges, and **Explosive barrel** in the
inventory, or obtain them from **Esc → Dev Bag**. These are original game-balance
recipes. The existing starter loadout and saved inventories are preserved.

- Carbine: left mouse fires, right mouse aims, R reloads a 30-round magazine.
- Ranger assault rifle: hold left mouse for automatic fire (100 ms shot interval),
  right mouse aims, R reloads. Uses Ranger cartridges and an independent 30-round
  magazine. Original mesh, moving magazine and icons; the existing rig supplies
  carry, aim, reload, equip and holster, with shortened firing recoil.
- Barrel: equip it, then right-click nearby clear ground to place one. Gunfire or
  melee damage ignites it. Nearby barrels can chain-react.
- Esc → Player → **Structural integrity and collapse** enables the optional
  support simulation. It defaults off and is saved with each world. Blast damage
  and flying debris still work while the integrity option is off.

Clicking fire with an empty magazine automatically starts a reload when matching
cartridges are available. R remains available for manual reloads. The trader
automatically equips the newly gifted Ranger after the first expedition handoff,
using an empty toolbelt slot or swapping the active slot into the backpack when
the belt is full. Existing carried items are preserved.

The existing `Human.r11.glb` contains the carbine and all ten first-person clips:
idle, walk, run, jump, aim, aimed fire, hip fire, reload, equip and holster.
Third-person rifle locomotion, aim, fire and reload clips are also reused.
No external gun or animation pack was imported.

## Runtime ownership

`combat_world.gd` is a bounded event adapter. Native inventory owns carried items;
`NativeCombatState` owns magazine, integrity preference and queued destruction
snapshot validation. Reload consumes cartridges only when the authored animation
finishes. Switching item, opening a menu, losing focus, or changing world cancels
the reload without consuming ammunition. Magazine state is stored separately for the player's
carbine and Ranger weapon types; individual copies of one type share a magazine.
Snapshot v3 preserves both, including migration from v1/v2 with an empty Ranger
magazine. Projectile payloads are captured at launch, independent of later equip.

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

The final source journey passes 33 creation and 11 fresh-process restore checks
in `reports/combat_world/20261101T183058376372Z`. This includes two actual carbine
shots damaging and igniting a placed barrel, followed by its chain reaction.
The reopened world retains exact
ammunition, barrel damage, crater density, destroyed cells, the integrity setting
and an interrupted blast cursor. Its completed prefix is not damaged again.
The native/animation suite passes 66, isolated debug/release native suites pass
46 each, melee timing/durability pass 27/21, and quests pass 53 per native variant.
The issue tracker retains exact report paths, native hashes, failed fixture runs,
and reviewed images. The HUD overlap/clipping and blast damage label are corrected.
No offscreen test captures the desktop pointer.

The combined native libraries are committed in `579a21c1`. The existing root
`TerraForest.exe` also passes the 33+11 journey with the exported package in
`reports/combat_world/20261101T185025193271Z`. All fourteen DLLs match the export;
strict sampled resource gates and zero pointer-capture assertions pass. The PCK
SHA-256 is `4295d8f9717cda70175cba36671fc10b259f39e0b8b6454f2fed6211d3a14afe`.
Rifle, reload, blast and crater screenshots from that executable are reviewed.
Run `python tools/check_combat.py --executable` to reproduce this gate without
replacing the user-owned executable. User visual review remains separate.

Original code is 0BSD. Original procedural barrel, icons and synthesized sound
data are CC0-1.0; inherited rifle and character provenance is preserved. Exact
paths and origins are in `addons/player_runtime/COMBAT_PROVENANCE.txt`.

## Ranger addition - 2026-11-01

The Ranger is newly authored original geometry with retained editable Blender
source, CC0 asset notice and 0BSD generator. The source combat journey passes
51 creation + 12 reopen checks; native state 53 per variant, full animation/state
79, melee timing/durability 27/21. Final aim framing and geometry connections were
visually reviewed, then the actual root executable passed 51 creation + 12 reopen
checks with all fourteen matching DLLs and strict sampled resource gates. Report:
`reports/combat_world/20261101T202958692951Z/run.json`; final PCK SHA-256
`1229d8b836902aa74c67352997ecfb0fc17a58c878c46e6c30b4f93f446da881`.
Source is committed in `9b12130f`, combined native artifacts in `b4d1c063`.
See [Ranger evidence](../issues/ranger-assault-rifle/README.md).
The earlier carbine-only package hashes above are retained historical evidence.
