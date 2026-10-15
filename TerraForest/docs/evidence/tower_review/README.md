# Grounded tower checkpoint — 2026-10-15

Command: `python tools/check_enclosed_cottage.py --grounded --tower`

The shared building runner cloned the canonical combined world and used ordinary
site survey, grading and supported placement to install the enclosed three-floor
tower. Some shared log labels still say "cottage"; the placement log identifies
the actual furnished tower, and the fixture selects its 61-attachment definition.

The actual main-world native player walked through the open entrance, around
both stair landings to the third floor, and returned downstairs. The normal world
saved; a fresh Godot process restored exact hinge state, door transform and window
identities, then closed the door through E. Source canonical hash unchanged.
The successful copy was published to the new `tower_review` slot. Existing slots
are never overwritten. `Review Tower.cmd` opens it without recreating the fixture.

`obstructed_view.png` was inspected: nearby foliage blocks much of the exterior
camera, so this image is not accepted as a clear visual review of the grounded
tower. The earlier isolated enclosure image remains the clear assembly view.
Human visual review and stairwell guards are pending. Startup receive hitches are
retained in logs; the run does not establish city-scale or thermal performance.
