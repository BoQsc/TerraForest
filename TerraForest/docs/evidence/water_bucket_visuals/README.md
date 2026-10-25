# Water bucket visuals — 2026-10-25

`Water-bucket.preview.mp4` shows the actual runtime model and character in first
and third person: ready, walking, pouring, scooping and running at normal animation
speed. The pail has 16,700 triangles and embedded metal/wood PBR maps. `ready.png`
is the studio comparison sheet, `world_filled.png` and `world_empty_pour.png` show
real water operations, and `icon.png` is the rebaked static inventory image.

Verification retained here:

- `runtime.json`: 36 checks for dense PBR geometry/UVs, repaired hand mesh,
  unchanged grip/fingers, root stability, event-free actions, seams, inventory
  fill states, use/placement/equip transitions and walking/running selection.
- `world.json`: 11 checks through the actual native world, inventory and mouse
  collect/pour/recollect flow, including correct authored motion and water visibility.
- `import.json`: 59 unchanged R11 rest bones and the six imported clips.

Shared attack timing (27), accepted pickaxe (11), pickaxe locomotion (24), character
runtime, inventory drop (16) and targeted character packaging also pass. The
accepted axe/pickaxe assets are unchanged. The tool icon dependency receipt was
refreshed after adding the new resources.

The new visuals await user playtest. The lower pail is partly cropped in first
person, and close-up skin/sleeve finish inherits the existing rig. The interior
uses a simple fill-state surface; there is no slosh simulation or pouring stream.
The existing native transaction is completed before its cosmetic use gesture;
this work does not redesign transfer timing or alter the gameplay water unit.

The first world render used a single large animation advance and caught the old
crossfade endpoint. Captures now advance normal frame increments. Preview capture
throughput and background-world HUD frame rates are not performance benchmarks.
Rebuild steps: `addons/characters/authoring/Human.bucket.README.md`.
