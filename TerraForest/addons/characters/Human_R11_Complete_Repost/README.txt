HUMAN R11 - REPOST PACKAGE / 2026-10-20
=====================================

Contains the original 2026-10-19 R11 character files, saved source report,
plus a newly assembled small Godot inspection viewer.

ENTRY POINTS
------------
- For the original game-ready model: open Godot_Viewer/models/Human.r11.glb
  in Blender, a glTF viewer, or another compatible 3D editor.
- For editing: open Human.r11.blend in Blender.
- For the Godot viewer: import Godot_Viewer/project.godot into Godot 4.4+.
- For animation comparison: play Human.r11.review.mp4.
- Read R11.validation.txt for the detailed original validation.

R11 MODEL
---------
- 14,997 triangles including character/equipment
- 59 bones
- 71 original 3P and 1P animations
- Experimental right-hand-led pickaxe grip with supporting left hand
- Original/default grip and right-lean/tilt swing variations preserved
- Work/Field/Trail outfit geometry; short hair option
- Preexisting pickaxe, axe, compact carbine
- Source records the character as CC0-1.0

OPTIONAL AK-47
--------------
Godot_Viewer/addons_optional/AK47_Ammo_Under15k.glb is a separate rifle
sample (14,307 triangles, 6 animations) and can be toggled as a detached
visual reference in the viewer. It is NOT integrated with Human R11, and
its clips are not part of the 71 character clips. Source: AK47_Ammo_Readme.txt
and AK47_Ammo_Under15k.blend.

IMPORTANT DISTINCTION
---------------------
The original FirstPersonLab.r11.zip was a 468 MB production Godot project
with dedicated controls and detailed raw test evidence. The original large
zip is in your Library but could not be materialized for this response.
This new Godot_Viewer is not the original production project: it is an
independent small inspection scene using the exact original R11 GLB.
Its source and every saved original R11 asset are preserved separately.
The replacement Godot viewer could not be executed in the packaging
container (Godot binary unavailable): test the scene in Godot 4.4+.

HUMAN SHA-256
------------
Human.r11.glb: 0dc8fdbcfac451f61b6eee5c914b1e79f5ec450f5e98e4c896e8b46370bf35c8
Human.r11.blend: 8ad2d2c2d570f9adfa487cfd469957ff61b4fbe172f0b60d28a44529b8d822d3

No external Python packages were used to package these files.
