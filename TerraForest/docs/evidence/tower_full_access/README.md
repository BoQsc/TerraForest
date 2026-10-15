# Full three-floor tower access, 2026-10-15

The previous tower movement test assembled three floors but traversed only the
first flight. The --all-floors option now uses the same native player capsule,
movement and real tower_floor prefab collision to walk the first flight, cross
its landing via the side corridor, climb the second flight, descend it, return
around the landing and descend to the original floor. Eight recorded landing
poses verify horizontal arrival, expected elevation and grounded support.
Tall-wall and low-ceiling rejection checks still run afterwards.

The first extended check failed because it evaluated floor height immediately
when horizontal distance reached its threshold, before downhill settling ended.
The corrected helper stops horizontal input and permits ordinary gravity/floor
snap to finish within the existing180-tick waypoint deadline. It does not move,
teleport or snap the body itself. All eight assertions pass with unchanged
runtime code and prefab data. Failure and corrected evidence are retained.

Command: python tools/run_godot_check.py tower_traversal --headless --timeout40
--require 'PASS low ceiling prevents unsafe step-up' -- --all-floors
(Use separate --timeout 40 arguments.)

This is headless movement correctness, not visual/performance qualification,
a furnished tower, a main-world integration check or arbitrary high-rise scale.
The original one-flight test remains available without the option. No water,
canonical saves, native DLLs or player movement code changed.

Next M2 building coverage: place a furnished multi-storey prefab in the combined
terrain world, exercise its complete access route, save/reopen, then inspect it
visually before claiming detailed large-building coverage. Existing furniture,
stack composition and site preparation should be reused.
