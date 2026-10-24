# Fixed-grip pickaxe - accepted default, 2026-10-24

After trying this version in the live temporary world, the user said it was
definitely better and explicitly requested default selection and a commit.
The default is now `FP_Pickaxe_Fresh_Swing` with its matching hold, 1.7-second
cycle and frame-50 (0.833 s) contact. Movement retains that fixed hold. The old
pullback remains an explicit alternate. Historical "pending", "current default"
and "do not commit" labels below/in the retained media describe the earlier
review stage; this acceptance supersedes them.

The user accepted a restart from fresh poses after explicitly rejecting the
weighted derivative as cartoonish and unnatural. This blockout starts on the
original neutral R11 rig, with newly authored body/weapon poses, a new hold,
firm fixed grips and 1.7-second duration. Earlier swing actions and the
rejected experiment were not used as motion sources. Static fitted finger
closure is reused from the original rig to preserve the mesh's hand anatomy.

The user rejected the initial sliding hand because it felt annoying for the
player and asked for a strong hold. The current revision keeps both complete
hand transforms fixed relative to the shaft throughout the action: left at
-22 cm and right at +11 cm along the shaft, with constant closed finger poses.
The tool trajectory and body timing are retained. No sliding or regripping is
left in the swing or recovery. Prior videos/reports are preserved under
`rejected_sliding_grip/`; they do not describe the current revision.

Previews:

- `Pickaxe.firm-grip-blockout.mp4`: simultaneous first-person and body views.
- `Pickaxe.current-vs-firm-grip.mp4`: current left, fixed-grip blockout right, each at
  its own duration and contact time. Both have the same camera and stage.
- `Pickaxe.firm-grip-first-person.mp4`: larger view of the new first-person motion.

Each is ten seconds at 30 FPS, with two normal-speed strokes and one half-speed
stroke. No effects, hit sounds or camera shake are added. The target is a fixed
studio marker aligned to this new strike; current/new contact paths and timing
are not forced to match. This is not a live collision or mining demonstration.
The older `Pickaxe.fresh-*`, `Pickaxe.current-vs-fresh.mp4` and `regrip.png`
filenames are historical sliding-grip previews retained for existing chat links;
use the `firm-grip` videos for the accepted motion.

Movement references consulted on 2026-10-24:

- [Inland Waterways Association, Hand Tools - Use, Care and Maintenance, page 7](https://www.waterways.org.uk/wp-content/uploads/2021/04/Hand-Tools-Use-Care-_-Maintenance.pdf#page=7):
  pick/cutting-mattock lift and guided descent. Its sliding-hand detail was
  superseded by the user's explicit fixed-grip requirement.
- [Appalachian Trail Conservancy / Jolly Rovers demonstration](https://appalachiantrail.org/the-register/pick-mattock-safety-tips-with-the-jolly-rovers/):
  inspected the visible stance and tool-handling demonstration in its embedded
  video. This is reference-informed original animation, not motion capture.

The first internal poses exceeded arm/leg reach and were corrected before
export. A pelvis offset initially used local rather than world coordinates;
that was corrected and a small knee bend retained. The first rendered hold
cropped the head and the load passed too near the camera; the hold pitch and
shoulder-side placement were revised before the delivered render. The final
raised head still goes above the first-person frame, and the lower grip falls
below the low hold/contact frame. The side view exposes the full movement.
The user accepted the movement after hands-on review. Further wrist/sleeve finish,
camera composition and dedicated lower-body locomotion are documented follow-ups;
they were not silently added to the version the user accepted.

The original nine runtime integrity checks covered default isolation, independent clip duration,
event-free animation tracks, new hold seams, fixed feet/root, full fixed hand
transforms without axial travel, continuous sampled rotations, actual cutting-point
descent and preservation of normal swing selection. These do not prove visual
quality or realism. The six baseline hashes describe preservation during review;
default promotion intentionally changes `human_view.gd` afterward.

Default integration passes eleven skeleton/mesh/selection checks and thirteen
graphical world checks using the ordinary scene, inventory equipment, real mouse
input and native terrain. They verify no early damage at the old contact time,
one excavation at frame 50, one wear increment, mining reward processing, full
recovery and cancellation on switching to the axe. The normal tool-view signal
check and existing character/alternate tests also pass. These are functional
checks; precise physical mesh-tip alignment with arbitrary targets is unqualified.

The first world-check attempt used headless Godot, which cannot capture the mouse
and therefore correctly rejected attacks. The graphical retry passed interactions
but reported an unsupported main-window hide call; removing that call produced
the clean passing offscreen run. Failed logs remain under
`reports/pickaxe_fresh/`; the final checks and acceptance record are retained here.
The temporary-world launcher now exercises ordinary default routing. Rebuild
and playtest instructions are in
`addons/characters/authoring/Human.pickaxe_fresh.README.md`.

Broader checks remain visibly partial: `human_placement` passes the changed
pickaxe hold/swing/recovery/restoration assertions but fails two block-placement
and terrain-fill policy assertions amid concurrent placement work. Those policies
are not changed in this commit. The full package suite reports seven existing
bundle/dependency failures, also reproduced using its unchanged HEAD test file.
The targeted character bundle check passes and includes the new runtime library.
See `acceptance.json` for scope and results; no general all-tests-pass claim is made.
