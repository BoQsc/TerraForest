# Right-side angled forward pickaxe — uncommitted review draft

**User visual approval is pending. Do not commit or merge this draft until the
user approves the animation.** It remains only in the character worktree.

The current review video is **`Human.pickaxe_forward_reduced_twist_v4.mp4`**. It shows two
normal-speed swings and a half-speed pass against a fixed studio target. The
actual runtime rig, equipment and 75-degree vertical camera are sampled manually;
this is animation review, not live mining, collision or performance evidence.

The strike draws back on the right, drives the working point forward with a
left diagonal, and finishes with a short follow-through in front. The hands and
handle remain on the right at contact; left shaft roll is reduced from 20–24
degrees to 6–8 degrees, with only one degree of torso turn. The working point
stays 16–17 cm to the right of the aim line, keeping the tool on that side while
reducing the twist. Recovery returns to the
same diagonal ready hold. The initial sideways sweep and the subsequent overly
centered forward pose were both superseded after user review.

## Current motion and checks

The action is 1.2 seconds, frames 0–72 at 60 FPS. The drive occupies frames 20–38,
with contact at 32, a brief forward follow-through, and recovery from 43 to 72.
The working point is the original mesh's sharpened tip, rather than the center
of its metal head. It advances about 31 cm in depth from wind-up to contact,
ending slightly to the right of the aim line. Its short continuation drops about
7 cm while remaining in front. The handle stays roughly 20 cm to the right.

`pickaxe/` retains the final actual-world engineering run: **23 checks pass**. It checks evaluated
working-tip forward travel, its diagonal approach toward the aim line, right-side
hands/handle and metal head, a left shaft roll below 12 degrees through contact,
a bounded follow-through, fixed
hand attachments, static root and a matching end/ready pose. It also exercises
actual belt selection, real-time return to idle, repeated input, hide/suspend,
walking/running, tool cancellation, placement restoration and empty-hand idle.
These checks do not approve visual quality; pose, hand deformation, crop and
swing timing still require the user's review.

The ready hold and Idle/Walk/Run/Jump clips are unchanged from the first draft.
Left support and right leading hand stations remain about 16.8 cm apart along
the handle, with a 7.9 cm vertical wrist difference in the diagonal ready pose.
The original R11 model, 71 clips, 59-bone rest rig, equipment, materials and skin
are preserved; the separate library adds five actions beside relaxed placement.
Each uses 177 bone tracks and 530 zero morph resets, clearing pose-specific
correctives belonging to older actions. There are no gameplay/method/audio tracks.
The body motor, mining scheduler, damage admission, cooldowns and saves retain
their existing ownership. No terrain/native code is changed by this draft.

The unchanged adapter/hold had earlier passing placement (29) and character
runtime (31) checks, retained in `placement/` and `character_runtime/`. Those
runs predate the swing-only revisions; the final actual-world pickaxe run above
covers the revised action and its controller transitions. Packaging and Python
syntax results are in `package_and_syntax.log`; exact source/asset hashes are in
`asset_hashes.json`. The rendered studio and world poses were inspected.

## Rejected and superseded observations

- `rejected_side_sweep_v1/` retains the user-rejected sideways sweep, its video,
  source and prior checks. Those checks measured the wrong motion goal; passing
  them did not make it the requested forward strike.
- `superseded_centered_forward_v2/` retains the forward revision's stills/source.
  The user said it was better but too centered. Its upright central contact is
  replaced by the right-side angled contact. That interrupted revision has no
  completed video of its own.
- `superseded_excess_left_twist_v3/` retains the next right-side forward draft,
  rejected for too much left twist. Its 20–24 degree roll and 3–4 degree torso
  turn are reduced to 6–8 degrees and one degree in the current draft. The angle
  check now caps excessive left rotation rather than requiring the previous
  strong inward tilt; the head must also stay on the right. The user requested
  that revised visual goal. The older video's link is retained for comparison.
- `right_hold_adjustment/` retains a 22-pass/one-failure observation: the right
  wrist drifted to 12.1 cm right of center at the deepest follow-through, below
  the 13 cm bound. The follow-through was shifted 2 cm right and checked again;
  the forward strike and inward angle were retained.
- `initial_hand_height_failures/` retains the first draft's two 19-pass/one-failure
  runs. The original test imposed an unrequested 10 cm vertical wrist gap, rather
  than measuring the upper/lower hand stations along the tilted handle. That
  fixture was corrected without changing the ready pose.

Editable source and rebuild commands:
`../../../addons/characters/authoring/Human.pickaxe_diagonal.README.md`.
The source `Human.pickaxe_diagonal.blend` contains the selected swing action,
phase markers and a first-person editing camera. User approval remains required
before any commit or synchronization to the active terrain checkout.
