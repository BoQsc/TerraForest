# Hammer and shovel

`Human.hammer.blend` and `Human.shovel.blend` are separate editable Human R11
sources. Select `Human_Rig`, choose an `FP_Hammer_*` or `FP_Shovel_*` action,
and scrub the marked timeline at 60 FPS. Each has Idle, Walk, Run, Jump and
Swing actions. The original R11 delivery and runtime body GLB are unchanged.

The repair hammer has a one-handed grip, a one-second strike, contact at frame
28 and two flush machined faces without a projecting peen. The shovel has two
fitted hands, a 1.4-second thrust/lever/recovery and contact at frame 34. Its
cutting end leads the shaft forward by 25 degrees while the concave inside of
the scoop remains visible to the player. The raised socket is on the back.

The complete tool meshes have 10,544 triangles (hammer) and 17,096 triangles
(shovel). The heads use dense curved surfaces, smooth normals and embedded
1024px brushed-steel base-color, roughness and normal maps, with metallic steel
and a separate machined-edge material. The `.blend` files pack these maps.
The runtime GLBs and baked pickup meshes retain the same PBR materials.
The shovel blade has no rectangular shoulder treads. Runtime import keeps the
maps embedded and uncompressed (`gltf/embedded_image_handling=3`).

## Rebuild

From the TerraForest directory, run Blender against the preserved source once
for each tool:

```powershell
$blender = 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe'
& $blender --background --disable-autoexec addons/characters/Human_R11_Complete_Repost/Human.r11.blend --python tools/author_hammer_shovel.py -- hammer
& $blender --background --disable-autoexec addons/characters/Human_R11_Complete_Repost/Human.r11.blend --python tools/author_hammer_shovel.py -- shovel
godot --headless --path . --script res://tools/import_hammer_shovel.gd
godot --headless --editor --path . --import
godot --headless --path . --script res://tools/ensure_item_icons.gd
```

The authoring script exports animation-only GLBs under `authoring/` and rigid
tool GLBs under `runtime/assets/`. The importer verifies all 59 rest bones
against R11, retargets only bone transforms, clears old pose-specific morph
correctives, and saves compact animation libraries. The rigid tools attach to
the existing `Weapon_Axe` and `Weapon_Pickaxe` bones, with the rest-axis
conversion removed once. Gameplay events remain in the existing live contact
adapter; animation contains no world mutations or body integration.

`tools/preview_hammer_shovel.gd -- --video` captures first-person ready,
windup, contact and recovery poses, a third-person grip view, two full-speed
swings and one half-speed pass under `reports/hammer_shovel/`. Encode them with
Blender factory startup and `tools/encode_hammer_shovel_preview.py`.

## Gameplay

The repair hammer keeps item ID 3. The assembly tool keeps ID 4. The new shovel
is ID 5 with 200 durability. Craft it for two wood and two metal, or use the
developer pickup spawner. Existing starter belts and saved inventories keep
their contents; loading a save never grants the new item for free. Hold left
mouse to dig/attack. The shovel uses normal 3.5 m reach, bounded native terrain
excavation and mining rewards; damage/wear resolve once at the visible contact.

Validation: `tests/attack_animation_timing.gd`, `tests/hammer_shovel.gd`,
`tests/gameplay_loadout.gd` and `tests/inventory_drop.gd`. The world/input check
needs a rendered Godot window, gameplay construction, `--temporary`, and
`--no-zombies`. See `docs/evidence/hammer_shovel/README.md` for the scope and
visual-review status.
