# Arc-swing test copy

The user liked the deeper pullback, then requested a separate test with slight
rightward tool twist and a swinging motion throughout instead of a push. This
copy comes directly from that kept Blender source and remains uncommitted.

The action adds a five-degree rightward tilt during the stroke, fading into the
kept ready endpoints. Curved wind-up leads into an elliptical lower-grip path,
with the tool rotating around that grip. A curved lower recovery completes the
cycle. The torso remains neutral. At frame 32 the actual sharpened point reaches
the same forward contact location as the kept version. The rest of the motion
has been deliberately revised for this test.

`Human.pickaxe_arc_swing.mp4` is an eight-second studio review using the actual
runtime rig and 75-degree camera: two normal-speed swings and a half-speed pass.
The helper window is minimized for SubViewport capture. Stills cover ready,
wind-up, approach, contact, follow-through and ready recovery. At the widest
wind-up the head nearly leaves the right edge and parts of the grip are below
the frame. Motion, crop and recovery remain subject to user visual review.

`result.json` and `check_pickaxe_arc_swing.log` retain 12 passing scoped checks.
Measured lower-hand forward travel is 10 cm versus 21.8 cm in the kept copy;
the tool rotates about 49 degrees from wind-up to contact. All three phases have
curved grip travel, both hands remain attached, root/torso stay fixed, contact
has five degrees of extra rightward tilt, and the action returns to its kept
ready pose. These engineering checks do not approve the visuals or qualify
gameplay collision, mining cadence or world performance.

The source assertion and preservation manifests cover 31 files from all three
kept candidates, including their source assets, runtime libraries, tools, tests,
videos and the normal-game adapter. All remain unchanged. This trial library is
injected only into the review fixture; normal gameplay still selects v4.
Nothing was staged, committed, merged or synchronized with terrain work.

Editable source and rebuild commands:
`../../../addons/characters/authoring/Human.pickaxe_arc_swing.README.md`.
