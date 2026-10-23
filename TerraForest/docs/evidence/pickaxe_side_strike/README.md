# Side-strike review copy

Fresh derivative of the preserved v4 Blender source, requested on 2026-10-23.
The new action changes the attack to a lower right-side wind-up and a forward
diagonal strike. The preserved ready grip and 1.2-second duration remain.
Both rejected leftward-continuation experiments are excluded as motion sources.
The user subsequently called this a good alternate and asked to keep it while
trying a separate deeper pullback. Its animation files remain unchanged; the
new copy is documented in `../pickaxe_side_pullback/README.md`. This alternate
has not been committed or selected by normal gameplay.

`Human.pickaxe_side_strike.mp4` shows two normal-speed swings and a half-speed
inspection pass using the actual runtime character, tools and 75-degree camera
in a fixed studio. The helper window is minimized during SubViewport capture.
Review stills include the ready grip, side wind-up, approach, contact, short
follow-through and ready recovery. The widest wind-up partially crops at the
right/bottom edges, as visible in the retained images. The studio target has no
collision; this recording does not validate live mining or world interactions.

The isolated runtime fixture passed 12 checks: separate animation selection,
no gameplay events, static root/torso, attached hands, matching first/last ready
poses, lower side approach, forward cutting-point travel, right-leaning shaft,
bounded continuation and return to the preserved idle/controller selection.
`result.json` and `check_pickaxe_side_strike.log` retain those results. Their
success does not approve animation appearance. Import retained the 59-bone rest
rig, with no changes to the R11 runtime model or skin.

The Blender source assertion and `baseline_verification.json` verify the exact
kept source and all eleven preserved v4 files. The normal game still selects v4;
only the review preview injects `Human.pickaxe_side_strike.res`.
No changes were staged, committed, merged or synchronized into terrain work.

Editable source and commands:
`../../../addons/characters/authoring/Human.pickaxe_side_strike.README.md`.
Keep this alternate intact when making further copies. Replacing the default
or committing the work remains a separate decision.
