> Integration update, 2026-10-23: the user authorized committing and syncing
> the pickaxe work. The deeper-pullback side strike is the game default; the
> arc-swing copy remains an unselected visual experiment. Earlier review-state
> instructions below are historical. See the character addon README.

# Diagonal pickaxe — review draft

**User approval is pending. Do not commit or merge this draft until the user
approves the animation.** It is integrated only in the character worktree.

Open `Human.pickaxe_diagonal.blend` in Steam Blender. The selected R11 rig action
is `FP_Pickaxe_Diagonal_Swing`, frames 0–72 at 60 FPS (1.2 seconds). Timeline
markers identify ready, chamber right, forward contact, short follow-through
in front and recovery.
`Pickaxe First Person` matches the runtime's 75-degree vertical camera FOV.
Studio lighting and camera-ray head masking are confined to this derivative.

The ready handle leans 38 degrees toward the player's right. The left hand takes
the lower support station and the right hand leads from the upper station, using
the source R11 right-grip finger wraps. Both hands stay attached to the tool.
The sharpened point drives **forward from the right toward the target**, frames
20–38, with contact at frame 32. Hands/handle remain to the right of the aiming
point and the shaft has only a small inward roll (6–8 degrees in the authored
tool pose, reduced from the previous 20–24 degrees). Torso turn is reduced to
one degree through contact. The working point stays slightly farther right,
so reducing the twist does not pull the whole tool back into the center.
The small left/down follow-through stays in front, followed by a separate slower
recovery to the original ready pose. This replaces the rejected sideways sweep
and the subsequent overly centered contact pose.
The supplied Idle, Walk, Run and Jump actions keep this diagonal grip; lower-body
locomotion is sampled from the original matching right-grip clips.

The original source blend, runtime R11 model, 71 source clips, materials, skin,
rest rig and physical player motor are preserved. A new AnimationLibrary supplies
the five actions. Its morph tracks clear the original pose-specific body/sleeve
correctives instead of reusing shapes fitted to a different arm pose. No method,
audio, gameplay, damage, collision, mining-cadence or save tracks are added.

Rebuild from TerraForest (the scripts contain the 0BSD license header):

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/Human_R11_Complete_Repost/Human.r11.blend --python-exit-code 1 --python tools/author_pickaxe_diagonal.py
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tools/import_pickaxe_diagonal.gd
python tools/run_godot_check.py pickaxe_diagonal --timeout 120 --require 'PICKAXE_DIAGONAL checks=' -- --gameplay-construction --zombies
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --fullscreen --resolution 1920x1080 --script res://tools/preview_pickaxe_diagonal.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/encode_pickaxe_diagonal_preview.py
```

`Human.pickaxe_forward_reduced_twist_v4.mp4` is an eight-second studio video showing two normal-speed swings and one half-speed
inspection pass. It uses the actual runtime rig, equipment and camera with manual
animation sampling against a fixed target; it is not a live mining, collision
or performance recording. The head can reach the right edge while drawing back
and the lower grip is partly below the
normal HUD. Pose, hand deformation, crop and timing remain subject to user review.
`diagonal_pickaxe=false` on `human_view.gd` selects the original pickaxe actions
for comparison. The original axe and relaxed placement action remain selectable.
