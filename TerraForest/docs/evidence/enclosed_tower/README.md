# Enclosed furnished tower — 2026-10-15

The furnished tower authoring function now closes the front façade at each floor,
adds a ground-level hinged entrance with an approach stair, seals the roof, and
omits the final flight that otherwise led into the roof. Stairwell openings needed
by the lower flights remain. The original bare tower module is unchanged.

Twenty checks pass with all attachment collision resident: door obstruction and
opening, capsule entrance, two-flight ascent and descent through landings, and
tall-wall/low-ceiling rejection. The headless run passed first; the rendered run
also passed at 1920x1080 with a 60 FPS cap. `tower.png` was inspected: roof and
front wall are closed and the window bands fit the pillars. This is assembly QA,
not a performance benchmark or a finished architectural-art claim.

Command:
`python tools/run_godot_check.py tower_traversal --timeout 45 --require "PASS low ceiling prevents unsafe step-up" -- --all-floors --furnished --visual`

Pending: grounded tower review in the combined world, additional interior detail,
stairwell guards, density/long-run qualification and human playtesting. The existing
cottage review save is unchanged.
