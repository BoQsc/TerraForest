# Deeper pullback — review copy

The user liked the preceding side strike as a good alternate and asked for a
copy that swings farther toward the player before launching the strike. This
Blender derivative adds 8 cm of preparatory pullback at frame 20, blending in
after frame 4 and out by frame 28. Frames 28–72, including contact and recovery,
and the ready pose match the liked side action. Tool orientation and neutral
body pose are preserved at every frame. The original alternate remains intact.

`Human.pickaxe_side_pullback.mp4` is an eight-second rendered studio review on
the actual runtime rig/camera, with two normal-speed and one half-speed action.
The closer wind-up increases the existing right/bottom crop, visible in
`chamber_right.png`. Approach, contact and recovery were also inspected. The
studio target does not simulate collision; this is not live mining evidence.
The user subsequently reviewed this as better and requested a separate test copy
with a slight rightward twist and swinging motion throughout. This deeper-pullback
version is retained unchanged; see `../pickaxe_arc_swing/README.md` for that test.

`result.json` and `check_pickaxe_side_pullback.log` retain nine passing scoped
checks comparing both imported animations: copied bone poses outside the changed
wind-up, tool/body orientation, fixed hand attachments, cutting-point depth,
one-shot duration, event-free tracks and preserved default/idle behavior.
These checks do not approve the animation's appearance.

`baseline_preserved.json` and `baseline_verification.json` cover 21 files from
both kept versions, including editable sources, runtime libraries, tools, tests,
videos and the game adapter. All hashes match after this work. The normal game
still selects v4; both side variants are loaded only for review. Nothing was
staged, committed, merged or synchronized with terrain work.

Editable source and rebuild commands:
`../../../addons/characters/authoring/Human.pickaxe_side_pullback.README.md`.
