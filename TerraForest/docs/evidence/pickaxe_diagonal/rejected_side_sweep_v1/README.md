# Diagonal pickaxe — uncommitted review draft, 2026-10-23

**Visual approval is pending. The user explicitly requires approval before any
commit. This draft belongs only to the character worktree and has not been
merged into the active terrain checkout.** Engineering checks do not approve
the appearance of the animation.

`Human.pickaxe_diagonal.mp4` shows the actual first-person runtime rig at its
normal 75-degree vertical FOV: a diagonal ready hold, two ordinary-speed swings
and one half-speed inspection pass. It is eight seconds of deterministic samples
encoded by Steam Blender 5.2.3 LTS, not live mining or runtime performance evidence.
The head reaches the side of the frame on the wind-up/follow-through; the lower
hand is partly hidden by the normal belt HUD. Pose, hand deformation, crop and
timing remain subject to user review. The studio and actual-world images were
inspected; user acceptance remains open.

The left hand supports the lower handle and the right hand leads above it.
The handle leans 38 degrees toward the player's right. The fitted hand stations
are approximately **16.8 cm apart along the handle**, giving a **7.9 cm vertical
wrist difference** at the diagonal ready pose. Both hand transforms stay fixed
relative to the tool. The R11 right-grip finger wraps are retained; forearm roll
and elbows are authored to follow the new path without extending bone lengths.

The 1.2-second strike is frames 0–72 at 60 FPS. It chambers on the right, strikes
from the upper right to lower left during frames 20–40, then recovers to the same
ready pose. In the actual 1920x1080 world-camera check, evaluated steel-head
centers move from approximately `(1766, 487)` to `(320, 723)` pixels during the
strike, continuously right to left. Recovering to ready is a separate phase.

The derivative Blender file includes five new Idle/Walk/Run/Jump/Swing actions,
the original meshes/rig, an editing camera and studio lights. Lower-body movement
comes from the original matching R11 right-grip actions. The runtime loads a
separate AnimationLibrary with 177 bone tracks and 530 constant-zero morph
resets per clip. Resetting the original pose-specific body/sleeve correctives
prevents a previous action's fitted deformation from being reused on new bones.
There are no method/audio/gameplay tracks or animated root movement. All 59 rest
transforms match the original rig within 0.000000241.

The original runtime GLB and Blender package remain unchanged; all 71 source
clips plus relaxed placement coexist with the five additions. The optional
`diagonal_pickaxe=false` switch selects the original pickaxe actions. Body motor,
damage admission, quarter-second mining scheduler, 1.2-second tool-versus-zombie
cooldown, collision and save ownership are unchanged. No native terrain or world
performance claim follows from the animation work.

## Retained engineering checks

- `pickaxe/`: **20 checks pass** in a disposable actual-world host. The real belt
  selects the new hold; evaluated steel-head motion verifies direction and
  diagonal travel. Both hand attachments stay fixed and all 59 end/start bone
  poses match. Real-time playback returns to idle; repeated input does not reset
  an active swing; hidden presentation pauses the timer; walking/running,
  equipment cancellation, placement restoration and empty idle remain functional.
- `placement/`: the existing **29 placement checks pass**, including accepted
  native block/terrain-fill feedback, neutral placement wrist and restoration
  of the new pickaxe hold. New capture was disabled for this unchanged gesture.
- `character_runtime/`: **31 existing character checks pass**, including rig,
  equipment/action selection, actual native zombie movement and combat.
- Scoped character packaging and Python syntax checks pass. `asset_hashes.json`
  records the source, tools, original runtime asset and new library.

The final Blender studio-camera/light setup was re-exported after the checks;
the imported runtime AnimationLibrary remained **byte-identical** to the tested
resource. No animation or gameplay change followed the successful checks.
The test's one-shot log label was subsequently clarified to refer to the existing
melee cooldown; its assertions and behavior were unchanged.

## Failed draft check retained

`initial_hand_height_failures/` retains two runs with 19 passes and one failure:
an initial test required a 10 cm **vertical** wrist separation. The requested
slightly staggered hands measure 7.9 cm vertically when the handle is tilted.
The first-person images show the right hand higher. The final check verifies
that it is above the left and at least 15 cm farther up the **handle**, instead
of imposing an unrequested 10 cm vertical gap. No animation geometry or motion
was changed to satisfy that test correction. The later actual-belt fixture also
replaces direct view-only equipment selection; its captured HUD matches the tool.

Rebuild commands and editing notes are in
`../../../addons/characters/authoring/Human.pickaxe_diagonal.README.md`.
Commit/merge remains blocked specifically on the user's requested visual approval.
