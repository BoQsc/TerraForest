# Relaxed placement action — 2026-10-23

The final action holds the whole right hand low with a **neutral wrist aligned
with the forearm**. The index is softly extended; the other fingers are loosely
curled and the thumb retains its natural opposition. The initial interpretation
that bent the wrist downward was rejected by the user and replaced.

`FP_Place_Relaxed` is authored in Steam Blender 5.2.3 LTS on the original 59-bone
Human R11 rig: 0–27 at 30 FPS, 0.9 seconds. It eases in, makes a small forward
placement emphasis, then returns. Editable source and rebuild commands are in
`../../../addons/characters/authoring/README.md`. The intermediate GLB supplies
the skeleton/action; only a compact AnimationLibrary is loaded by the game.

The original R11 GLB SHA remains
`0dc8fdbcfac451f61b6eee5c914b1e79f5ec450f5e98e4c896e8b46370bf35c8`.
All 71 original clips remain available, alongside this new clip. The converter
checks all rest transforms (maximum error 0.000000241) and preserves constant
base-pose tracks so previous equipment cannot distort the placement pose.
The 177 retained tracks affect bones only: no gameplay methods, audio, physical
body integration or root-motion events. Asset and tool hashes are retained.

## Verification and review

- `placement/`: all 22 actual-host checks pass. These include accepted native
  block placement, removal not starting placement feedback, queued terrain fill,
  uninterrupted held input, selected-equipment restoration, neutral wrist,
  low hand position, visible index fingertip above the belt, and identical hand
  pose after different equipment. The save is a disposable test world.
- `character_runtime/`: 31 checks, zero failures. Original tools, rig import and
  bounded zombie behavior remain functional with the additional library.
- `character_world/`: 18 checks, zero failures with the intended rendered
  `--gameplay-construction` launch. Actual belt, zombies, melee, wear, wooden-block
  damage/destruction and unchanged encounter save schema pass.
- The scoped character packaging check passes and now requires the placement
  resource in dependency bundles. Both Blender Python tools pass syntax checks.

`preview.png`, the Blender detail image and the actual-world images were
inspected. They show the corrected neutral wrist, low position and relaxed hand.
`Human.placement.mp4` is a clean studio preview of the identical runtime rig and
camera, encoded by Blender from 57 deterministic 30 Hz samples. It is animation
review, not real-time performance evidence. World quality, tool wall clipping,
other construction grips and authored empty-hand punches remain open.

## Superseded and failed checks

`earlier_cropped.png` retains the earlier unsuitable first-person framing and
wrist-flex interpretation. The final pose and framing replace it. Constant pose
tracks are retained in the final converter, avoiding residual tool/torso poses.

`wrong_headless_world_launch/` retains a failed invocation with four failures:
it omitted gameplay construction, leaving encounters disabled, and headless mode
cannot establish captured mouse input for the paid attack path. The unchanged
world fixture passes all 18 checks in its intended rendered gameplay launch.
This was a launcher error; no gameplay guards were weakened to make it pass.
