# Water bucket hands/use revision 2 — 2026-10-25

The user rejected the original hands and actions. `Water-bucket.preview.mp4`
shows the reworked 2.8-second supported pour and 2.4-second scoop at normal speed,
with first-person, close support-hand and whole-body views. It also shows ready,
walk and run. The 10-second video uses the actual imported runtime assets.
`ready.png`, `pour.png` and `scoop.png` are studio sheets. `world_dip.png`,
`world_filled.png` and `world_empty_pour.png` show actual water operations.
`icon.png` is the updated static inventory image with the taller bail.

Verification retained here:

- `runtime.json`: 63 checks for dense PBR geometry/UVs, the repaired hand mesh,
  fixed right grip/fingers, coincident bail ears, stationary support intervals,
  wrist bend below 50 degrees, sampled forearm clearance, actual skinned finger/
  palm contact without floor penetration, root stability, event-free actions,
  seams, fill timing, equipment transitions and walking/running selection.
- `world.json`: 13 checks through the actual native world, inventory and mouse
  collect/pour/recollect flow, including the delayed visual fill/empty beats.
- `import.json`: 59 unchanged R11 rest bones and the six imported clips.

Shared attack timing (27), accepted pickaxe (11), pickaxe locomotion (24), character
runtime, inventory drop (16) and targeted character packaging also pass. The
accepted axe/pickaxe assets are unchanged. The tool icon dependency receipt was
refreshed after adding the new resources.

The revised visuals await user playtest. The lower pail and support hand are
partly cropped in first person, and close-up skin/sleeve finish inherits the existing rig. The interior
uses a simple fill-state surface; there is no slosh simulation or pouring stream.
The existing native transaction is completed before its cosmetic use gesture;
this work does not redesign transfer timing or alter the gameplay water unit.

The first implementation's short handle and single-pulse gestures were rejected.
Rework iterations exposed a bent support wrist, raised elbow, pail/forearm
intersection, arm-roll sign flip between keys and fingertips through the floor.
The final assets correct these; the regression checks include 120 Hz interpolation
and CPU skinning of the actual runtime palm. Forearm clearance uses a conservative
sampled pail envelope, not an exhaustive triangle/triangle collision proof.
Ordinary short animation crossfades remain bone interpolation, not a runtime IK lock.

The first world render used a single large animation advance and caught the old
crossfade endpoint. Captures now advance normal frame increments. Preview capture
throughput and background-world HUD frame rates are not performance benchmarks.
Rebuild steps: `addons/characters/authoring/Human.bucket.README.md`.
