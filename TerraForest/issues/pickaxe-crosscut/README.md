# Separate pickaxe animation study

- Status: Raised-hold / cursor-strike revision, unapproved. Accepted default remains selected.
- Updated: 2026-10-26. Implementation/evidence: commit adding this record.
- User review: First candidate rejected as “absolutely not what was asked or wanted.”
  User clarified the strike must travel **upper right → lower left**.
- The resulting candidate (`241a4b88`) was also not accepted after playtesting:
  the user wanted the pickaxe held higher toward the top-right corner and the
  strike aimed toward the cursor. Its impact was about 41 cm below camera center.
- Request: More diagonal holding pose and a descending strike with a firm grip;
  promote only after explicit user approval.

## Images and previews

![Latest raised hold against current default](images/raised-hold.png)

Left: accepted default. Right: latest raised diagonal carry. Matching 16:9
first-person views, 75-degree vertical FOV and neutral lighting. The back end
of the head reaches the top/right edge; the shaft and both grips are visible.

![Latest cursor-aligned contact](images/raised-contact.png)

The cutting point reaches the fixed central crosshair at gameplay contact.
The target is fixed on the camera centerline, independently of the animation.
Right pane shows the body and grip. This is a projection/alignment check;
the finite-length model does not move to every possible gameplay hit distance.

![Latest down-left follow-through](images/raised-follow.png)

The follow-through continues below and left of the cursor. Both hands remain
fixed; the lower hand/shaft can leave the bottom-left edge during the strike.

[Latest comparison video](Pickaxe.raised-cursor.comparison.mp4)
and [latest first-person/body video](Pickaxe.raised-cursor.body.mp4).
Two swings at normal speed, one at half speed, then walking. Each version keeps
its own timing. Godot 4.7.2 Forward+, RTX 4050, 2560×820 composite. No world/seed
for these views. Source paths, status and hashes are in `images/manifest.json`.

### Earlier evidence, not accepted

![First candidate rejected at impact](images/rejected-contact.png)

First candidate straightened at impact and read as a forward chop.

![Second candidate, low hold](images/comparison-hold.png)

Second candidate carried too low and struck below the cursor. Its original
[comparison](Pickaxe.upper-right-to-lower-left.comparison.mp4),
[body video](Pickaxe.upper-right-to-lower-left.body.mp4), and
[contact](images/revised-contact.png) remain intact. These use 4:3 panels and
a target placed at that candidate's contact, so their target mark was not a
central cursor. The latest preview uses 16:9 and an independent central crosshair.

## Implementation and verification

Separate Blender source, GLB and AnimationLibrary: `Human.pickaxe_crosscut.*`.
The pose table uses the original R11 rig and static finger wraps; no accepted
swing keys are copied. This revision raises the ready head by about 49 cm
relative to the second candidate and targets camera center at contact. It has
a short descending follow-through and recovery to the raised diagonal hold.
Both hands stay at fixed stations, -22 cm and +11 cm along the shaft.
The right hand's closed grip is seated 30 degrees farther around the handle
for this version, keeping its elbow lower and farther from the camera. That
orientation is constant throughout the animation; neither hand slides.
It is baked at 120 Hz to keep interpolation drift small during the fast stroke.
Idle, swing, walk, run, jump and derived crouch belong to this candidate.

Ordinary runtime code and the accepted pickaxe libraries are unchanged. Only
the explicit experimental tool-view subclass selects this library. Its contact
is 0.7 seconds (frame 84 at 120 Hz), and its complete cycle is 1.6 seconds.
Gameplay remains on the existing attack/contact/cancellation pipeline.

Qualification results, per-frame measurements and preserved-default hashes are
in `qualification.json` and `verification/`. They verify scoped mechanics;
they do not establish that the new motion is visually better.

26 candidate checks cover 1,902 poses sampled at 240 Hz, including the raised
ready head and the actual skinned cutting point at the cursor centerline.
Grip interpolation must remain below 1 mm / 0.3 degrees; arms must remain
within the wrist/rotation bounds. Thirteen actual-world checks cover excavation and
one durability change at contact, recovery and cancellation. The accepted
pickaxe's 11 checks and locomotion's 24 also pass. Runtime log frame-42 labels
refer to the 60 Hz pose table; the exported action uses frame 84 at 120 Hz.

## Try and compare

From TerraForest, start Godot with `--path . --script
res://tools/playtest_pickaxe_crosscut.gd -- --temporary --gameplay-construction
--ground-cover --no-zombies`. The launcher always uses temporary storage.
**F6** switches between the revised candidate and the accepted default. It
cancels an active stroke before switching. Select the pickaxe and use ordinary
movement/attack controls. Exiting does not promote the candidate or write a
player world. Launching the game normally continues to use the accepted default.

## Remaining / resume here

User review of the descending motion, raised diagonal carry, grip, framing and weight
is required. The source character's skin/clothing finish remains visible.
Further pose changes should be driven by the rejected/accepted moment, camera
view and animation time. Default promotion requires an explicit acceptance;
passing tests, committing the study or running the comparison is not acceptance.

The first and second candidates' local source snapshots remain under
`reports/pickaxe_crosscut/rejected_v1/` and `rejected_v2/`; their retained images
are in this folder. The second revision is also recoverable from `241a4b88`.
Regenerate the revision using `tools/author_pickaxe_crosscut.py` on the original
`Human.r11.blend`, then `tools/import_pickaxe_crosscut.gd`. Render with
`tools/preview_pickaxe_crosscut.gd` (`-- --stills` for key poses), then encode
with Blender and `tools/encode_pickaxe_crosscut_preview.py`.
