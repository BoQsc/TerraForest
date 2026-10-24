# Pickaxe walking correction

The approved fresh pickaxe was routed to static idle for every movement state.
The axe still selected movement animations. A separate Blender library now adds
Walk/Run/Jump using the approved tool hold and fixed hand stations. The approved
idle/swing assets are unchanged. The user subsequently accepted all current work,
including this movement follow-up, as the baseline on 2026-10-24.

`Pickaxe.locomotion.mp4` shows idle, walk, run and stop at normal animation speed,
with first-person and third-person views of the actual runtime rig. This six-second
studio capture is not a gameplay FPS benchmark. Native walking is checked separately.

Verification:

- 24 rig/controller checks: moving tool, exact baked grip transforms, between-key
  interpolation, fixed finger wraps, root stability, seamless loops, velocity
  selection, stop, swing priority/recovery and unchanged axe routing.
- 8 graphical native-world checks: actual movement at 5.5 m/s and 9.9 m/s selects
  Walk and Run respectively; the weapon moves and stopping restores accepted idle.
- 11 accepted-pickaxe checks and 27 shared attack-timing checks pass. Character
  runtime and the targeted character package check also pass.

The existing 0.1-second crossfade interpolates bones independently. Measured hand
deviation peaks at 4.34 mm and 0.98 degrees across idle/walk/run transitions, inside
the regression bounds of 5 mm/two degrees. The within-clip grips stay fixed; no
slide/regrip is authored. This is not an exact post-blend runtime IK constraint.
Close sleeve/knuckle finish remains the accepted rig's existing limitation.

The first world attempt used a hyphenated temporary slot name that the terrain
loader rejects. The corrected identifier passes. No native terrain changes were
needed for this animation work, and the temporary world did not save player data.

Rebuild instructions are in
`addons/characters/authoring/Human.pickaxe_locomotion.README.md`.
