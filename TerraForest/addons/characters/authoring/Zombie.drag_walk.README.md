# Weighted limping walk, revision 2

Open `Zombie.drag_walk.blend` in the installed Steam Blender. The selected
`Zombie_Rig` has action `Zombie_Walk_Drag_Right`, frames 0–120 at 60 FPS: a
two-second loop. The left leg supports 68% of the cycle, rolling from heel to
toe before its lifted recovery. The right leg catches up late with a toe scrape,
then supports the left step. Sole trajectories match 0.9 m of travel per loop;
their recovery curves preserve velocity at the stance boundaries and loop seam.
The pelvis shifts about 10 cm between sides and compresses about 6 cm while
loading the weak leg. A distributed forward hunch, counter-rotating chest,
delayed head motion, uneven hanging arms, soft elbows and lagging wrists replace
the stiff idle-derived upper pose. Both legs remain attached; severed-leg
behavior still crawls.

The action is in place. Runtime standing pursuit uses the existing native
navigator and movement motor at a default 0.45 m/s, matched to the authored gait.
Measured horizontal body travel scales the following animation tick, including
injury slowdown and collision-limited motion. A blocked body holds its gait
instead of continuing to walk against a wall; clearing the obstruction resumes
the matched cadence. The
original R4 model and its 15 clips remain unchanged; the additional compact
AnimationLibrary is loaded beside them. Setting `dragging_walk=false` retains
the old walk selection and its original 0.72-m/s reference-speed calibration.

Rebuild from TerraForest:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/ZombieLab/source/Zombie.r4.blend --python tools/author_zombie_drag_walk.py
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tools/import_zombie_drag_walk.gd
python tools/run_godot_check.py zombie_drag_walk --headless --timeout 90 --require 'ZOMBIE_DRAG_WALK checks=24 failures=0'
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
gameplay/method/audio tracks or root translation. The twelve-second preview is
four normal-speed cycles from three-quarter and side views, followed by one
half-speed side cycle, moving over a marked studio floor at the matched speed.
That translation is preview-only. Functional tests run the real native
route/body owner separately. The current review and retained failures are in
[revision 2 evidence](../../../docs/evidence/zombie_weighted_limp/README.md).

Flat-floor skin checks establish toe clearance, left-foot lift and a continuous
loop seam. They do not provide terrain foot IK, plant feet on arbitrary slopes,
or authorize new steps/jumps/ladders. The existing collision profiles, injury
rules, navigation limits, attacks and save format remain authoritative.
