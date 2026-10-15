# Window component — 2026-10-15

Production object palette now includes a 2 × 2 m wooden frame with transparent
glass. Offline authoring creates two shared mesh surfaces (72 triangles total).
Existing native static batches own storage, rendering and bounded nearby collision.
There is no per-window scene script or update loop. Existing object attacks remove
the entire window; independently breaking glass while retaining the frame is pending.
Four wood is a provisional recipe, not a completed glass crafting economy.

Command: `python tools/run_godot_check.py window_component --headless --timeout 30 --require "WINDOW_COMPONENT failures=0"`

Checks cover production scene parsing, catalog registration, material surfaces,
stable placement, pane collision, removal clearing collision, and exact snapshot
restoration with collision. This does not qualify rendered appearance, transparency
overdraw, full compound restart, attack gameplay, or city-scale performance.

Next: functional doors with persistent hinge state, safe collision transitions and
normal E interaction; then furnished tower placement and a human review checkpoint.
