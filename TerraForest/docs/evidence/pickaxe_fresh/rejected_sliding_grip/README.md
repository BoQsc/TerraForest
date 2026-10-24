# Fresh pickaxe blockout - pending user motion review

The user accepted a restart from fresh poses after explicitly rejecting the
weighted derivative as cartoonish and unnatural. This blockout starts on the
original neutral R11 rig, with newly authored body/weapon poses, a new hold,
sliding right-hand grip and 1.7-second duration. Earlier swing actions and the
rejected experiment were not used as motion sources. Static fitted finger
closure is reused from the original rig to preserve the mesh's hand anatomy.

Previews:

- `Pickaxe.fresh-blockout.mp4`: simultaneous first-person and body views.
- `Pickaxe.current-vs-fresh.mp4`: current left, fresh blockout right, each at
  its own duration and contact time. Both have the same camera and stage.
- `Pickaxe.fresh-first-person.mp4`: larger view of the new first-person motion.

Each is ten seconds at 30 FPS, with two normal-speed strokes and one half-speed
stroke. No effects, hit sounds or camera shake are added. The target is a fixed
studio marker aligned to this new strike; current/new contact paths and timing
are not forced to match. This is not a live collision or mining demonstration.

Movement references consulted on 2026-10-24:

- [Inland Waterways Association, Hand Tools - Use, Care and Maintenance, page 7](https://www.waterways.org.uk/wp-content/uploads/2021/04/Hand-Tools-Use-Care-_-Maintenance.pdf#page=7):
  pick/cutting-mattock lift, guided descent and sliding upper hand.
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
Wrist/finger/sleeve finish, camera composition and the feeling of the action are
still user review items; a rough blockout does not close them.

Nine runtime integrity checks pass: default isolation, independent clip duration,
event-free animation tracks, new hold seams, fixed feet/root, grip attachment
with axial hand slide, continuous sampled rotations, actual cutting-point
descent and preservation of normal swing selection. These do not prove visual
quality or realism. Six original source/runtime hashes are preserved.

The current default is unchanged. User acceptance of this movement is required
before polish, locomotion adaptation, contact/timing integration and eventual
default selection. No commit or gameplay integration has been made. Rebuild
instructions are in `addons/characters/authoring/Human.pickaxe_fresh.README.md`.
