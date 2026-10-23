> Integration update, 2026-10-23: the user authorized committing and syncing
> the pickaxe work. The deeper-pullback side strike is the game default; the
> arc-swing copy remains an unselected visual experiment. Earlier review-state
> instructions below are historical. See the character addon README.

# Side-strike copy — visual review pending

This is a separate derivative of the preserved `Human.pickaxe_diagonal.blend`
(SHA256 `fc19d70c8209b01f996e2658ccf2f424b93fb766928e27a3c3a2caba3ddd8351`).
Neither rejected continuation was used as its motion source. The preserved
source, runtime library and normal gameplay selection remain unchanged.
The user requires this work to remain uncommitted.

Open `Human.pickaxe_side_strike.blend` in Steam Blender. The selected action is
`FP_Pickaxe_SideStrike_Swing`, frames 0–72 at 60 FPS. The copy retains the kept
ready grip and original finger wraps, draws back lower to the right at frame 20,
and drives diagonally forward to contact at frame 32. A short continuation ends
at 38, followed by recovery to the exact ready pose at 72. The shaft leans right
throughout; the torso remains in its neutral ready pose. The new library contains
only this swing; it is loaded by the review preview, not normal gameplay.

Rebuild from TerraForest:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/authoring/Human.pickaxe_diagonal.blend --python-exit-code 1 --python tools/author_pickaxe_side_strike.py
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tools/import_pickaxe_side_strike.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tests/pickaxe_side_strike.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --resolution 640x360 --position '-2300,0' --disable-render-loop --script res://tools/preview_pickaxe_side_strike.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/encode_pickaxe_side_strike_preview.py
```

The preview minimizes its helper window and renders a 1920×1080 SubViewport
using the actual runtime rig/camera. Its eight-second video shows two normal-speed
swings and a half-speed pass. The wind-up reaches the right screen edge, partially
cropping the head/hand at its widest point. This remains subject to visual review.
It is a studio capture, not a live collision/mining demonstration.

See `../../../docs/evidence/pickaxe_side_strike/README.md` for preserved-file
verification and the scoped engineering results. No commit or terrain sync.
