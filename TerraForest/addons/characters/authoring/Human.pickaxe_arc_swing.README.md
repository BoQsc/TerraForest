> Integration update, 2026-10-23: the user authorized committing and syncing
> the pickaxe work. The deeper-pullback side strike is the game default; the
> arc-swing copy remains an unselected visual experiment. Earlier review-state
> instructions below are historical. See the character addon README.

# Arc swing with slight right tilt — separate test copy

Copied directly from the liked `Human.pickaxe_side_pullback.blend`. The preceding
versions and normal gameplay selection remain unchanged. This test is uncommitted
and awaits user visual feedback.

Open `Human.pickaxe_arc_swing.blend` in Steam Blender. The selected action is
`FP_Pickaxe_ArcSwing_Swing`, frames 0–72 at 60 FPS. Wind-up follows a curved path;
the main stroke rotates the tool around the lower grip while that hand follows
a shallow ellipse. A lower curved recovery returns to the exact kept ready pose.
The tool receives a five-degree additional rightward tilt during the action,
blending away at both ready endpoints. The torso stays neutral.

Contact remains at the kept target location, frame 32. From wind-up to contact,
the lower grip advances 10 cm instead of the prior 21.8 cm, while the tool turns
about 49 degrees. Thus the head's travel comes mostly from the rotational stroke.
The complete animation is intentionally revised; only ready endpoints and the
forward contact target are preserved exactly, not all intermediate poses.

Rebuild from TerraForest:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/authoring/Human.pickaxe_side_pullback.blend --python-exit-code 1 --python tools/author_pickaxe_arc_swing.py
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tools/import_pickaxe_arc_swing.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tests/pickaxe_arc_swing.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --resolution 640x360 --position '-2300,0' --disable-render-loop --script res://tools/preview_pickaxe_arc_swing.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/encode_pickaxe_arc_swing_preview.py
```

The preview minimizes its helper window and renders the actual runtime rig into
a 1920×1080 SubViewport. Its eight-second video has two normal-speed swings and
a half-speed pass. The head nearly leaves the right edge at the widest wind-up;
the lower grip remains partly cropped. Judge that crop and the motion in review.
It is a studio target, not a live mining/collision demonstration.
Evidence: `../../../docs/evidence/pickaxe_arc_swing/README.md`.
