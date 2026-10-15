# Furnished tower circulation — 2026-10-15

The default prefab palette now includes a three-floor furnished tower. Each floor
has two tables, two chairs, one shelf, one chest and fourteen window bands.
The authoring function accepts 2–16 floors, but this check qualifies only three.
Native prefab composition and the existing complete placement transaction own
the blocks and attachments. Furniture stays out of the central stairs and east
landing route. Existing bare tower assets are unchanged.

Command:
`python tools/run_godot_check.py tower_traversal --headless --timeout 45 --require "PASS low ceiling prevents unsafe step-up" -- --all-floors --furnished`

Fourteen checks passed, including all model collisions resident, native capsule
walking up both flights and around landings, returning to the bottom, and existing
tall-wall/low-ceiling rejection. Captured landing poses are in `landings.json`.
No human navigation or rendered-performance qualification is implied.

Remaining building work: close the roof and unfinished front façade, safe entry,
grounded placement, visual review, and higher-density combined-world testing.
The cottage review save remains available and unchanged.
