# TerraForest player model — animation & new-item handoff

This package is the playable first-person/third-person player character used by
TerraForest. The goal of the handoff: animate new first-person actions on this
rig and build one new held item, then send the results back for integration.
Nothing in this package is a mock-up — the `.glb` is byte-identical to the model
the game loads today.

- Model: **Human R11**, 1 unit = 1 metre, +Y up in the GLB (glTF standard).
  Standing height ≈ 1.81 m in bind space.
- Rig: one armature object named `Human_Rig`, **59 bones**, single skin.
- Geometry: 14,997 triangles (measured from the index buffers), 26 mesh objects,
  27 materials, 21 embedded PNG textures.
- Animation: **71 existing clips** (34 third-person, 37 first-person `FP_*`).
- License of the model: **CC0-1.0** (source note: "R7 original edits CC0-1.0;
  inherited asset provenance retained"). See `03_Docs/README.txt`.
- Everything below was read from the shipped file and from TerraForest's own
  import/integration code, not from memory.

---

## 1. What is in the package

| Path | Purpose |
| --- | --- |
| `01_Model/Human.r11.blend` | **Editable source.** Mesh, 21 packed textures, 59-bone rig, the 71 rig clips. Open this to animate. |
| `01_Model/Human.r11.glb` | The exact runtime model the game imports. Reference/target for comparison. |
| `01_Model/Human.r11.preview.png` | Render of the delivered character. |
| `01_Model/Human.r11.review.mp4` | Existing animation review capture. |
| `02_Example_Animation/Human.hammer.blend` | **Worked example of a held tool**: rig + hammer mesh + `FP_Hammer_Idle/Walk/Run/Jump/Swing` actions at 60 FPS. |
| `02_Example_Animation/Human.hammer_shovel.README.md` | Notes for that example (grip, contact frame, rebuild steps). |
| `02_Example_Animation/Human.unarmed.blend` | Worked example of an empty-hand first-person action (`FP_Unarmed_Idle`, `FP_Unarmed_Punch`). |
| `02_Example_Animation/Human.unarmed.README.md` | Notes for that example (timing, contacts, rebuild steps). |
| `03_Docs/README.txt` | Original delivery/provenance notes and SHA-256 of the model. |
| `03_Docs/R11.validation.txt` | Full original validation report. |
| `03_Docs/HANDOFF.md` | This document. |
| `04_Reintegration/*` | The two authoring (`author_human_*.py`) and two import-verification (`import_human_*.gd`) scripts TerraForest uses. Read them as the contract your export must satisfy. |

Blender 4.x/5.x opens the `.blend` files directly (packed with Blender 5.2.3
LTS when this package was built); any DCC that reads glTF 2.0 can inspect the `.glb`.

---

## 2. Rig

Root node `Human_Rig`. Bone names are **exact and fixed** — the game looks them up
by name, and the import step rejects the file if any rest transform moved.

Spine chain and limbs:

```
Root
 Hips
  LeftUpLeg -> LeftLeg -> LeftFoot -> LeftToeBase
  RightUpLeg -> RightLeg -> RightFoot -> RightToeBase
  Spine -> Spine1 -> Spine2
   Neck -> Head -> Eye.L, Eye.R
   LeftShoulder -> LeftArm -> LeftForeArm -> LeftHand
    LeftHandIndex1..3, LeftHandMiddle1..3, LeftHandPinky1..3,
    LeftHandRing1..3, LeftHandThumb1..3
   RightShoulder -> RightArm -> RightForeArm -> RightHand
    RightHandIndex1..3, RightHandMiddle1..3, RightHandPinky1..3,
    RightHandRing1..3, RightHandThumb1..3
```

Mount bones (the only ones equipment may be parented to):

| Bone | Used by |
| --- | --- |
| `RightHand` | torch (item 6), generic consumables/held items |
| `Weapon_Pickaxe` | pickaxe, shovel, held bucket |
| `Weapon_Axe` | axe, repair hammer, bucket bail |
| `Weapon_Carbine` | rifle body |
| `Weapon_Magazine` | rifle magazine |

Rules:

1. **Do not** rename, delete, add or reparent bones. The importer instantiates a
   fresh copy of `Human.r11.glb`, compares every bone's rest transform, and
   aborts when the count is not 59 or when any bone drifts more than 0.0001 m/axis.
2. Apply object transforms inside Blender; keep scale 1.0 on the armature.
3. Do not re-export the rigid item meshes out of the rig pose — see item rules in
   section 5.

---

## 3. Animation conventions

- Timeline: **60 FPS**, timeline starts at frame 0. (`FP_Place_Relaxed` is the one
  legacy 30 FPS clip; do not copy that exception.)
- One Blender Action per clip on the `Human_Rig` object; the Action name becomes
  the clip name in Godot.
- The source file holds 497 Action datablocks, because accessory, wardrobe and eye
  meshes carry their own `<Clip>.<Mesh>` copies. The game clip is the action on
  `Human_Rig` itself — the GLB exports exactly 71. If you edit an existing clip,
  keep the matching accessory actions consistent (or leave them untouched).
- First-person clips are prefixed `FP_` and describe the camera-relative motion.
  Third-person clips have no prefix (`Idle`, `Walk`, `Run`, `Jump`, `Crouch`,
  `Pickaxe_*`, `Axe_*`, `Rifle_*`). New first-person work must use `FP_`.
- Per-tool suffix vocabulary already in use:
  `_Idle`, `_Walk`, `_Run`, `_Jump`, `_Equip`, `_Holster`, `_Swing`, `_Swing_Right`,
  `_Swing_Tilt`. Follow it so the runtime's clip lookup keeps working:
  `FP_<WeaponName>_<Action>` (e.g. `FP_Hammer_Swing`).
- **Contact frame is authored data, not decoration.** The game schedules damage
  and tool wear from a contact time table keyed by clip name
  (`human_view.gd` `CONTACTS`), e.g. `FP_Hammer_Swing` = frame 28 of 60,
  `FP_Shovel_Swing` = frame 34, `FP_Pickaxe_Fresh_Swing` = frame 50,
  `FP_Unarmed_Punch` = frame 28. Tell us the contact frame for every new action.
- Looping: `_Idle`, `_Walk`, `_Run` loop; `_Swing`, `_Equip`, `_Holster` are
  one-shots that return to their idle pose.
- First-person actions must not move `Root`, `Hips`, or the legs/feet. Locomotion
  clips own those; the game plays the FP action on top of standing or moving.
  Full-body actions (new third-person clips) are a separate, explicitly agreed
  deliverable.
- Hands must stay on the authored grip stations for the whole clip when a tool is
  held; that is what keeps the rigid tool mesh glued to the hands
  (`02_Example_Animation/Human.hammer.blend` shows the accepted approach).
- Keep the four `Weapon_*` bones unanimated unless the item genuinely needs a
  bone-space offset; equipment placement is defined by those bones' rest pose.

---

## 4. Export and import contract

Export an **animation-only GLB** per batch (materials not needed), using the same
options TerraForest's authoring script uses:

```
export_format='GLB'
use_selection=True            # armature + body only
export_materials='NONE'
export_animations=True
export_animation_mode='ACTIONS'
export_frame_range=False
export_force_sampling=True    # every bone keyed, no constraints surviving export
export_skins=True
export_morph=False
export_yup=True
```

TerraForest then imports that file in Godot 4 with `animation/fps=60`,
`animation/import=true`, `animation/remove_immutable_tracks=true`, and copies only
bone tracks onto its own rig, saving a compressed `AnimationLibrary` (`.res`)
next to `Human.r11.glb`. The runtime model itself is imported with:

```
animation/fps=60
gltf/embedded_image_handling=2   # textures stay embedded (Basis compressed)
meshes/ensure_tangents=false     # source surfaces have no UVs everywhere
skins/use_named_skins=true
```

Follow those settings if you open the GLB in Godot yourself to check it; 30 FPS
or regenerated tangents will not match the game.

### Things that will be refused on return

- different bone names/count/rest pose, added helper bones, rescaled armature;
- clips that fail to import as named Actions, or clips whose duration changes
  silently (durations are asserted per clip on import);
- renamed mesh nodes or materials: first-person view hides the head by swapping
  materials whose name contains `Human.Head` / `Human.Mouth`, and clothing slots
  are keyed on node names `Hair.*`, `Wardrobe_FieldVest`, `Wardrobe_Boots`;
- non-CC0 third-party assets baked into the file.

---

## 5. Holding a new item

A held item is its own GLB, authored **in the rig's rest-pose model space**, then
exported with its transform baked. At runtime the game parents the item under a
`BoneAttachment3D` on the mount bone and applies
`skeleton.get_bone_global_rest(bone).affine_inverse() * item.transform`, which is
why the source mesh must sit where the hand/weapon bone rests — not at the world
origin. `02_Example_Animation/Human.hammer.blend` is exactly that arrangement:
the rigid mesh `Equipment.Hammer` (5,280 vertices) is parented under `Human_Rig`,
sits at the pickaxe/axe grip in the rest pose, and carries an `FP_Hammer_*` clip
set plus a `Hammer First Person` review camera.

Deliver for the new item:

1. The item mesh in the rig scene at the chosen mount bone's rest transform
   (right/left hand grip, or one of the `Weapon_*` bones).
2. A rigid item GLB with its own PBR materials and embedded, uncompressed texture
   maps (Godot import for tool GLBs uses `gltf/embedded_image_handling=3`).
   Pickup/icon renders reuse the same mesh, so keep it a single closed, sane-scale
   object (metres, real-world size).
3. Existing first-person tools are ≈10,500 triangles (hammer) and ≈17,100
   (shovel); stay in that range for a new tool.
4. A short text file stating: item name, mount bone, pivot/grip point, item length
   in metres, contact frame(s) of the matching `FP_*_Swing` clip, durability/behaviour
   notes, and triangle count.
5. Materials must not rely on the head/mouth material names used for first-person
   masking.

The TerraForest side (item ID, catalog entry, icon, durability, damage/terrain
rules, first-person visor masking) is handled here — you only deliver art,
animation and the metadata above.

---

## 6. What to send back

One archive containing:

- the edited `.blend` with only your new/changed Actions added on the untouched
  `Human.r11.blend` rig, textures packed;
- the animation-only `.glb` export;
- the item `.glb` (if you built one);
- a plain-text clip table: clip name, frame count, FPS, loop or one-shot, contact
  frame, and which hand(s) hold what;
- optional stills/video of the result;
- a note confirming the work is offered as **CC0-1.0** and identifying any
  third-party asset or tool used with its license.

Integration on our side, for transparency: the blend is placed beside
`Human.r11.blend`, `author_*.py` is run to re-export, `import_*.gd` verifies all 59
rest bones (max 0.0001), the clip table is added to `human_view.gd` (clip map and
contact times), Godot reimports at 60 FPS, then `tests/character_runtime.gd` and
`tests/character_world.gd` are run before it ships.

---

## 7. Reference hashes

See `03_Docs/SHA256SUMS.txt` for the hashes of every file in this package.
The runtime GLB must keep:

```
Human.r11.glb  SHA-256 0dc8fdbcfac451f61b6eee5c914b1e79f5ec450f5e98e4c896e8b46370bf35c8
```

(reference model, 52,440,320 bytes — 59 bones / 71 animations verified on packing)
