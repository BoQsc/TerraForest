# Held movement, belt wheel and excavation projection regression

2026-10-11. `input_surface_regression.gd`: 27 checks, zero failures, no engine errors.
Command: `python TerraForest/tools/run_godot_check.py input_surface_regression --timeout 80 --require "failures=0" -- --gameplay-construction`.

The main scene receives real input events: W remains held through all ten number
keys and actual flight displacement continues. Development entry/exit, tilde-F,
movement presses/releases during the chord, wheel wrapping through all ten slots,
empty hands, and menu/inventory scrolling are checked. Opening an actual menu still
clears movement. No native rebuild or save migration is required.

The visual fixture excavates a narrow vertical capsule using the native terrain
edit route, hides trees for visibility, waits for publication and renders the same
camera, geometry, material parameters and lighting with the old and new projection.
`before.png` shows elongated stones at the upper rim and side walls; `after.png`
removes these bands. Only texture projection weights change: smooth vertex normals
still supply lighting. Geometry face normals come from screen derivatives, adding
no texture fetches, geometry or render passes. Facet boundaries can still affect
projection blends; this does not change the mesh resolution or material art.

An initial visual attempt was obscured by trees. A second used material 3, which
legacy generator excavation paints as metal; the final fixture uses material 1,
as the pickaxe does. A wide sphere was also checked before narrowing the cavity
to expose the reported stretching more clearly. These were fixture revisions,
not additional production fixes.

Fullscreen 1920x1080, 60 FPS cap. This is a short functional/visual regression,
not a sustained-performance or thermal qualification. Saves use the launcher's
isolated temporary world. Full provenance and logs accompany the screenshots.
