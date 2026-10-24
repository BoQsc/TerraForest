# Fresh pickaxe - accepted fixed-grip default

This is a separate rough motion study authorized after the user rejected the
weighted derivative and requested a substantially new, realistic animation.
The user accepted the fixed-grip version during live play on 2026-10-24 and
explicitly requested default selection and a commit. This supersedes historical
pending-review labels in the original Blender metadata and preview reports.

The source is the original `Human_R11_Complete_Repost/Human.r11.blend`.
The authoring script resets the body to the rest rig and deletes the original
actions before creating new actions. It does not read any previous swing,
diagonal/pullback derivative or rejected weighted animation. Only a static
finger closure and hand orientation fitted to the shaft are reused from the
original R11 idle, to preserve the existing mesh's hand anatomy. The new hold,
body poses, stance, hand stations, strike path and timing are newly authored.

Actions in `Human.pickaxe_fresh.blend`:

- `FP_Pickaxe_Fresh_Idle`: static two-second blockout hold.
- `FP_Pickaxe_Fresh_Swing`: 102 frames at 60 FPS (1.7 seconds), contact at 50.
  Lift to the right shoulder, guide a downward stroke, settle and return with
  both hands firmly fixed on the shaft throughout. Grip stations are -22 cm
  and +11 cm relative to the tool pivot, with constant closed finger poses.
  Neither hand slides, releases or changes its station during recovery.
  Both feet stay planted while pelvis and torso carry a small weight transfer.
  The root and camera stay still.

The user rejected the initial sliding-hand version as annoying for the player
and required a strong fixed grip. That feedback supersedes the sliding-hand
detail from the original movement reference. Its rejected previews are retained
under `docs/evidence/pickaxe_fresh/rejected_sliding_grip/`.

The gesture is informed by the pick/cutting-mattock technique on page 7 of the
[Inland Waterways Association hand-tool handbook](https://www.waterways.org.uk/wp-content/uploads/2021/04/Hand-Tools-Use-Care-_-Maintenance.pdf#page=7)
and inspection of the [Appalachian Trail Conservancy demonstration](https://www.youtube.com/watch?v=hRINXwBOWYI).
The blockout is an authored interpretation for a high working target, not
motion capture or a claim of physical/visual realism. Realism needs user review.

Ordinary gameplay loads this library by default, using its 1.7 s duration and
frame-50 contact. The same hold remains active while moving. The temporary-world
launcher now uses normal runtime routing with no replacement subclass.
Dedicated lower-body locomotion, precise mesh-tip/target alignment and further
view/framing or finger/sleeve polish remain follow-ups, rather than changes to
the motion the user accepted.
At the raised pose, the tool head passes above the first-person camera frame;
the side view shows that portion of the action. The lower hand leaves the lower
frame at the low hold/contact. These are visible review points, not hidden
behind effects. Original R11 skin, materials and rest skeleton are unchanged.

Rebuild from TerraForest, using Steam Blender/Godot:

For interactive review, launch Godot with `--path . --script
res://tools/playtest_pickaxe_fresh.gd -- --temporary --gameplay-construction
--ground-cover --no-zombies --max-fps=60`. The launcher equips the candidate and
forces temporary storage. `-- --verify` instead checks the tool-view contact
signal and recovery without opening the world.

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/Human_R11_Complete_Repost/Human.r11.blend --python-exit-code 1 --python tools/author_pickaxe_fresh.py
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tools/import_pickaxe_fresh.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --headless --path . --script res://tests/pickaxe_fresh.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --windowed --resolution 640x360 --disable-render-loop --script res://tools/preview_pickaxe_fresh.gd
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/encode_pickaxe_fresh_preview.py
```

The preview supports `-- --stills`. For reliable automation of the Steam Godot
GUI executable use `Start-Process -Wait -WindowStyle Hidden` with separate stdout
and stderr files. Godot generates matching UID sidecars for new scripts.

The three ten-second previews show two normal-speed swings and one half-speed
swing. The current-vs-new comparison preserves each clip's duration; it does not
speed up the new action to match the current one. Review evidence is under
`docs/evidence/pickaxe_fresh/`.
