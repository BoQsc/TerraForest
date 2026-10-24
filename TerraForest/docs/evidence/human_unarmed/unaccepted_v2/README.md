# Neutral hands and punching - reworked after rejection, review pending

The first delivery was explicitly rejected for unnatural motion/keying and broken
hand deformation. Its passing functional checks did not establish visual quality.
`rejected_v1/` retains that version's video, stills, authoring script and reports.
The older `Unarmed.neutral-and-punch.mp4` is rejected evidence, not the current
preview.

`Unarmed.reworked-punch.mp4` is the current Godot runtime model in a neutral
studio: two punches at normal speed, followed by one at half speed. The rework
forms the fists first, accelerates from a compact preparation into a late turn,
retracts promptly along the strike path and relaxes after returning. Contact is
still at frame 18 / 0.3 seconds; the complete cycle is 54 frames / 0.9 seconds.
First-person frames throughout the stroke and front/side fist stills were inspected.

Both hands have repaired skin weights, removing pulls from neighboring fingers;
the off-hand's inverted orientation is corrected. The wrist stays aligned and
finger joints remain fixed while closed. The mesh variant preserves rest geometry,
UVs, materials and rig; equipping tools restores the original mesh. The original
tool-grip morph is no longer used to compensate for the bad weighting.

Current evidence is named `Reworked.*.png` and `reworked-*.json`. Coarse knuckle
creases and shirt/shoulder clipping are still visible in close third-person views.
User review of the new motion and hand shape remains open. Neither the test
results nor this preview claims user acceptance or finished wardrobe deformation.

The graphical world check (11 checks, zero failures) selects the actual empty toolbelt slot, sends real
mouse input and hits a real native block. It verifies windup without damage,
one ordinary 5-damage hit at frame 18, unchanged inventory/no tool wear, return
to neutral and cancellation when equipping the accepted pickaxe. Existing damage,
reach and target rules are retained. Twenty runtime checks cover pose seams,
planted root/feet, mirrored palms, fixed fist shape, normalized finger weights,
preserved mesh attributes, hidden equipment and restoration when switching tools.
All pass, alongside 27 attack-timing checks, 11 accepted-pickaxe checks, character
runtime regression and the targeted character package test. Unarmed Blender
authoring/import and preview render complete without errors. These are scoped
checks; the project's unrelated full-suite failures are not reclassified here.

Authoring/rebuild details are in
`addons/characters/authoring/Human.unarmed.README.md`. The six-second preview is
for appearance review; no commit has been requested for this new work.
