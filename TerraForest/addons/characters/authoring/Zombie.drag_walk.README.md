# Slow dragging-leg walk

Open `Zombie.drag_walk.blend` in the installed Steam Blender. The selected
`Zombie_Rig` has action `Zombie_Walk_Drag_Right`, frames 0–120 at 60 FPS: a
two-second loop. The left leg carries the weight for a long stance and then
takes a lifted recovery step. The right leg trails, with a raised heel and a
toe that scrapes forward. An asymmetric hip drop and restrained arm/head sway
support the limp. Both legs remain attached; severed-leg behavior still crawls.

The action is in place. Runtime standing pursuit uses the existing native
navigator and movement motor at a default 0.45 m/s, matched to the authored gait.
Actual motion speed scales playback, including existing injury slowdown. The
original R4 model and its 15 clips remain unchanged; the additional compact
AnimationLibrary is loaded beside them. Setting `dragging_walk=false` retains
the old walk selection and its original 0.72-m/s reference-speed calibration.

Rebuild from TerraForest:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/ZombieLab/source/Zombie.r4.blend --python tools/author_zombie_drag_walk.py
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tools/import_zombie_drag_walk.gd
python tools/run_godot_check.py zombie_drag_walk --headless --timeout 90 --require 'ZOMBIE_DRAG_WALK checks=16 failures=0'
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --fullscreen --resolution 1920x1080 --script res://tools/preview_zombie_drag_walk.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python tools/encode_zombie_drag_walk_preview.py
```

The Blender file preserves the original mesh, materials and 59-bone skeleton for
editing and includes two review cameras. The intermediate GLB exports a minimal
skin map and the action without materials. The Godot converter checks every bone
rest transform against the unchanged runtime model, retains constant pose tracks,
and copies neutral morph resets from the original walk. Previous mouth, knee or
clothing deformation must not survive an attack-to-walk transition.

The result has 177 bone tracks and seven neutral shape-key tracks, with no
gameplay/method/audio tracks or root translation. The preview is four sampled
cycles, from three-quarter and side views, moving over a marked studio floor at
the authored speed. That translation is preview-only. Functional tests run the
real native route/body owner separately.

Flat-floor skin checks establish toe clearance, left-foot lift and a continuous
loop seam. They do not provide terrain foot IK, plant feet on arbitrary slopes,
or authorize new steps/jumps/ladders. The existing collision profiles, injury
rules, navigation limits, attacks and save format remain authoritative.
