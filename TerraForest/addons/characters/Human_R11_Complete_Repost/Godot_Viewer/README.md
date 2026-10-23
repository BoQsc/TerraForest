# Human R11 — lightweight Godot animation viewer

This package repackages the **exact saved** `Human.r11.glb` from 2026-10-19 (51 MiB, 14,997 triangles, 59 bones, 71 animation clips) with a small, newly written viewer for Godot 4.4 or newer. The GLB is not rebuilt or modified.

## Run it

1. Unzip the package to a folder with enough free storage.
2. Start Godot 4.x and choose **Import**, then select this folder's `project.godot`.
3. Open the project and press **F6** on the `main.tscn` scene or **F5** to run the entire project.
4. Use on-screen controls to choose original versus experimental right-hand-led grip, animation style, outfit, equipped object, and an individual animation clip.

### Keyboard / mouse

- Right-mouse drag: orbit around the character in third-person mode; wheel: zoom.
- W/A/S/D: display movement animation; hold Shift to display running animation (character remains on its test platform).
- Left-click away from the UI: swing pickaxe/axe or fire carbine. Space: jump. C: crouch preview.
- 1: carbine; 2: pickaxe; 3: axe; 4: unarmed.
- G: toggle experimental pickaxe hand grip; J: rotate swing styles; F: switch rough first-/third-person camera; P: pause/unpause.
- The dropdown exposes **all 71 original GLB clips**, including first-person versions, so clips can be scrutinized without depending on the viewer's demo state machine.

### Contents

- `models/Human.r11.glb`: the exact source model, embedded PBR textures and all 71 animations.
- `addons_optional/AK47_Ammo_Under15k.glb`: independently modeled AK-47 sample from a different project. It can be made visible near the character for comparison. **It is not rigged or integrated into R11's rifle animation system.** R11 uses its existing compact carbine.
- `main.gd`, `main.tscn`, `project.godot`: independent viewer built for this repost.

### Limitations and authenticity

The original `FirstPersonLab.r11.zip` recorded in the source validation report is a **different, much larger, production test project** with specialized live state transitions, action queuing, test evidence and visual review. That original archive could not be directly extracted for this repost. This package is a **replacement viewer**, not a byte-for-byte copy of the original Godot project. Only `Human.r11.glb` is byte-identical to that project model. The viewer is not guaranteed to duplicate every first-person camera, grip switch/re-equip transition, or other runtime behavior of the full test lab. Godot is not installed in this packaging environment; open/run this project in your Godot installation to confirm behavior.

The character source records it as **CC0-1.0**, derived from a user-provided character with repaired geometry, revised UV/textures, authored equipment, rig and animations. See `R11.validation.txt` for the saved assessment. The optional AK-47's independent documentation is included in the full repost ZIP.
