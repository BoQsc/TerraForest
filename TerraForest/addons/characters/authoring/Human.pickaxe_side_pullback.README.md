> Integration update, 2026-10-23: the user authorized committing and syncing
> the pickaxe work. The deeper-pullback side strike is the game default; the
> arc-swing copy remains an unselected visual experiment. Earlier review-state
> instructions below are historical. See the character addon README.

# Side strike with deeper pullback — separate review copy

Derived directly from `Human.pickaxe_side_strike.blend`, the alternate the user
liked. That source and the earlier v4 are preserved unchanged. This copy is
uncommitted and is not selected by normal gameplay.

Open `Human.pickaxe_side_pullback.blend` in Steam Blender. Its selected action
is `FP_Pickaxe_SidePullback_Swing`, frames 0–72 at 60 FPS. Only frames 5–27 are
modified: the existing wind-up pulls an additional 8 cm toward the player,
peaking at frame 20 and smoothly rejoining the kept action at frame 28.
Tool orientation and torso pose match the liked version throughout. Both hands
retain their handle stations; arm bends accommodate the closer grip. Contact,
follow-through, recovery and the ready poses retain the exact copied bone keys.

Rebuild from TerraForest:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/authoring/Human.pickaxe_side_strike.blend --python-exit-code 1 --python tools/author_pickaxe_side_pullback.py
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tools/import_pickaxe_side_pullback.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tests/pickaxe_side_pullback.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --resolution 640x360 --position '-2300,0' --disable-render-loop --script res://tools/preview_pickaxe_side_pullback.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/encode_pickaxe_side_pullback_preview.py
```

The eight-second studio preview renders in a SubViewport while its helper window
is minimized. It shows two normal-speed strikes and a half-speed pass. The closer
wind-up moves more of the hand/tool outside the right/bottom camera edges; review
that crop and timing in the video. No gameplay collision/mining changes are made.
Engineering comparisons and source preservation are recorded in
`../../../docs/evidence/pickaxe_side_pullback/README.md`.
