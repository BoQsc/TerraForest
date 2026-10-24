# Fixed-grip pickaxe locomotion

The fresh pickaxe route previously mapped Walk, Run and Jump to its static idle.
That protected the new grip from incompatible older clips but froze the tool
while moving. `Human.pickaxe_locomotion.res` adds three separate actions using the
accepted idle's exact hand-to-tool transforms and fixed finger poses:

- `FP_Pickaxe_Fresh_Walk`: one-second loop; small lateral sway and two vertical
  step pulses, with restrained rotation around the hands.
- `FP_Pickaxe_Fresh_Run`: 0.8-second loop at 1.6 times the walk amplitude.
- `FP_Pickaxe_Fresh_Jump`: 1.5-second airborne settle, matching the accepted hold
  at both ends. The existing velocity controller determines airborne selection.

Lower-body keys come from the original R11 in-place body gaits. Fixed-length
arm solves follow the moving tool; both wrist transforms and closed finger poses
stay fixed relative to the shaft within each clip. The existing 0.1-second blend
between clips is evaluated separately: its independent bone interpolation briefly
deviates by up to 4.4 mm and one degree at the grip in the sampled transitions.
The regression bound is 5 mm/two degrees; this is not an exact runtime IK lock.
Keys are baked at 60 FPS. The native motor still
owns the player body. No methods, contact events or root motion are added. The new
pickaxe switches to running above 6.5 m/s, between the native 5.5 m/s walk and
9.9 m/s sprint speeds; other tools retain their current selection thresholds.

The accepted `Human.pickaxe_fresh.blend`, `.glb` and runtime `.res` are unchanged.
The user accepted the added library with the current-work baseline on 2026-10-24.
The measured blending and existing rig-finish limitations above remain documented.

Rebuild from `TerraForest` with the installed Blender/Godot executables:

```text
blender --background --disable-autoexec addons/characters/authoring/Human.pickaxe_fresh.blend --python-exit-code 1 --python tools/author_pickaxe_locomotion.py
godot --headless --path . --script res://tools/import_pickaxe_locomotion.gd
godot --headless --path . --script res://tests/pickaxe_locomotion.gd
godot --path . --windowed --resolution 640x360 --position -32000,-32000 --script res://tests/pickaxe_locomotion_world.gd -- --temporary --gameplay-construction --no-zombies
godot --path . --windowed --disable-render-loop --script res://tools/preview_pickaxe_locomotion.gd
```

The preview shows actual runtime first-person and third-person rigs at normal
animation speed, with idle, walk, run and stop transitions. It is a studio capture,
not a rendering-performance benchmark. Native movement is checked separately.
