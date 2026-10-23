# Relaxed placement gesture

Open `Human.placement.blend` in Blender. The selected rig has the action
`FP_Place_Relaxed`, with a 0–27 timeline at 30 FPS (0.9 seconds). Frame 13 shows
the placement pose. The hand is held low with a neutral wrist aligned to the
forearm, a softly extended index finger, loosely curled remaining fingers and the
original thumb opposition with mild flexion. The wrist is not bent downward.

The motion eases from the original empty idle into the low gesture, makes a small
forward placement emphasis, and returns. It has no root motion or gameplay event
tracks. The source contains the original R11 mesh and rig for editing, plus
`Placement First Person` and `Placement Hand Detail` cameras. Camera-ray masking
on head/mouth materials makes the first-person preview usable; runtime geometry,
materials and all 71 original animations remain in the unchanged R11 GLB.

Rebuild using the installed Steam Blender and Godot executables:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/Human_R11_Complete_Repost/Human.r11.blend --python tools/author_human_placement.py
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tools/import_human_placement.gd
python tools/run_godot_check.py human_placement --timeout 120 --require 'HUMAN_PLACEMENT checks='
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --fullscreen --resolution 1920x1080 --script res://tools/preview_human_placement.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python tools/encode_placement_preview.py
```

Run these commands from TerraForest. The first step produces the editable blend,
an intermediate material-free GLB and source metadata. This folder is excluded
from Godot's automatic import scan. The second step checks every bone's rest
transform against the original runtime rig and writes only the compact
`runtime/assets/Human.placement.res` AnimationLibrary. Constant pose tracks are
retained so an earlier tool pose cannot alter the hand's placement position.

The live-world check exercises block placement/removal, queued terrain fill,
input repetition and equipment restoration, and records first-person images.
The studio preview uses the identical runtime rig/camera and captures 57
deterministic samples for Blender's video encoder. The preview is animation
review, not a recording of real-time frame performance.

Only accepted single-block placements and accepted terrain-add submissions
trigger the gesture. Held input cannot restart it before it finishes. Visible
equipment is temporarily hidden and restored afterward; changing equipment
cancels it. Native placement admission, inventory, collision and save ownership
are unchanged. Other construction grips, punches and tool transitions remain
separate unfinished requirements.
