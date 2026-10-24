# Empty hands and punch

The first version was rejected by the user for unnatural timing/keying and broken
hand deformation. Its evidence is retained under
`docs/evidence/human_unarmed/rejected_v1/`. The second delivery is retained in
`unaccepted_v2/`: the user called the empty hands a useful baseline but explicitly
did not accept them, and rejected the punch as instant, awkward and flat, like
hitting UI. This third revision changes the rest pose, timing, body contribution
and bare-hand interaction distance. User appearance acceptance is still pending.

Blender-authored actions on the unchanged 59-bone R11 skeleton:

- `FP_Unarmed_Idle`: hands turned farther inward, a soft 12-degree wrist bend
  and loosely curved fingers near the bottom of the view; two-second static loop. First-person
  movement keeps this neutral hold.
- `FP_Unarmed_Punch`: 68 frames at 60 FPS (1.133 seconds). Both fists close by
  frame 8; the right hand draws in by frame 12 and extends over 16 frames into
  contact at frame 28 (0.467 seconds). The shoulder leads and the torso turns
  and inclines slightly. Withdrawal reaches the ready pose by frame 42, with
  the fists still closed. Both hands relax by frame 62 and settle at neutral.
  The loaded knuckle travels about 35 cm forward and 9 cm upward, giving the
  drive a stronger depth component than the previous upward screen movement.

Monotonic Hermite curves define wrist travel and timing, then every frame is
baked into bone keys. The elbow follows a fixed-length two-bone solve; the upper
arm follows its bend plane while the forearm pronates. The resting wrist bend
straightens completely as the fist closes, before the drive starts.
The thumbs wrap over the folded fingers, and the left hand uses the correct
mirrored palm orientation. The upper-arm basis no longer follows a palm-dependent
sign, which could flip its orientation around a 90-degree hand roll. Upper-body
rotation and a six-degree forward incline support the stroke;
root, hips and feet remain stationary. Third-person walking, running and jumping
retain the original locomotion clips. This is a first-person action, not a new
full-body boxing locomotion system.

`unarmed_hand_weights.py` repairs cross-finger influences in both hands: 1,061
source vertices, of which 209 had more than 10% weight from a neighboring finger.
Each repaired vertex blends only between its own finger joints and the palm.
The importer maps these onto 1,958 runtime vertices including UV seam copies.
The runtime variant retains the original positions, topology, UVs, materials,
skin bind and 228 blend-shape identities. Repacking the surface quantizes normals
and tangents again (maximum measured component/vector difference 0.00013).
The old tool-grip corrective is reset to zero; it is not used to conceal the
deformation. `Human.unarmed_body.res` is selected only for item 0, and equipping
any tool restores the exact original body mesh. The accepted pickaxe is unchanged.

Selecting an empty inventory/toolbelt slot equips item 0 and this neutral hold.
Left mouse uses the existing world-attack pipeline with the new punch contact.
Bare hands previously inherited the tools' 3.5 m query. Their reach is now 0.72 m,
matching the visible fist surface at roughly 0.64 m with a small contact allowance.
The shared nearest-surface and occlusion query still checks the live target at
impact for blocks, zombies, terrain and other eligible targets. Tool reach stays
3.5 m; damage values and target permissions are unchanged. Empty hands do not
consume durability. Placement continues to use `FP_Place_Relaxed`.
Tool switching or losing attack eligibility cancels an unfinished punch.

First-person neutral, closure, extension, contact and recovery, plus front and
side views of the fist, were inspected from the actual Godot model. The original
mesh still shows coarse knuckle creases and shirt/shoulder clipping in close
third-person views. Those limitations remain visible and tracked; engineering
checks do not approve anatomy or motion quality on the user's behalf.

Rebuild from TerraForest with Steam Blender/Godot:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/Human_R11_Complete_Repost/Human.r11.blend --python-exit-code 1 --python tools/author_human_unarmed.py
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tools/import_human_unarmed.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tests/human_unarmed.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --windowed --resolution 1280x720 --script res://tests/human_unarmed_world.gd -- --temporary --gameplay-construction --no-zombies --video
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/encode_human_unarmed_preview.py -- --world
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --disable-render-loop --script res://tools/preview_human_unarmed.gd -- --video
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/encode_human_unarmed_preview.py
```

Omit `--video` to capture neutral/contact/recovery stills from first-person,
body, front and hand-detail cameras. `Unarmed.world-contact-v3.mp4` records actual
temporary-world block contact: one normal-speed punch followed by one at half
speed. This is a frame-captured visual check, not a performance recording.
`Unarmed.depth-stroke-v3.mp4`, when rendered, is the corresponding studio
view. The world input test requires a
graphical backend because headless Godot does not support mouse capture.

Motion reference: the rear straight punch's late forearm turn and withdrawal in
[Boxing Canada's beginner coaching reference](https://boxingcanada.org/wp-content/uploads/2025/01/Instruction-Beginners-Reference-Manual-EN.pdf).
