# Neutral hands and punching - user review pending

The user requested a neutral hand pose with an empty belt slot and a distinct
punch when attacking unarmed. `Human.unarmed.blend` authors both actions on the
original R11 rig. Ordinary runtime item 0 selects the new neutral hold and
0.8-second punch, with one contact at 0.3 seconds. Placement remains separate.

`Unarmed.neutral-and-punch.mp4` is the actual runtime model in a neutral studio:
two punches at normal speed, followed by one at half speed. Stills include the
neutral pose, contact and side/detail views. First-person and close-detail frames
were inspected during iteration. The original skin's wrist twist and uncorrected
knuckle collapse were addressed; remaining coarse finger and shirt deformation
needs user visual review. Functional checks do not approve appearance.

The graphical world check selects the actual empty toolbelt slot, sends real
mouse input and hits a real native block. It verifies windup without damage,
one ordinary 5-damage hit at frame 18, unchanged inventory/no tool wear, return
to neutral and cancellation when equipping the accepted pickaxe. Existing damage,
reach and target rules are retained. Separate runtime checks cover pose seams,
planted root/feet, wrist alignment, hidden equipment and placement restoration.

Authoring/rebuild details are in
`addons/characters/authoring/Human.unarmed.README.md`. The six-second preview is
for appearance review; no commit has been requested for this new work.
