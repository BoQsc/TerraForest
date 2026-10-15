# Building interaction prompts — 2026-10-15

The main world now displays `E · Open wooden door`, `E · Close wooden door`
or `E · Open wooden chest` beneath the crosshair when aiming within 3 metres.
One native scene ray supplies both component target resolvers. Presentation
updates at most 10 times per second, without catch-up bursts. E performs a
fresh ray; cached presentation never authorizes an action. The existing native
hinge occupancy guard and container storage path remain authoritative.

Menus, inventory, flight, driving, focus loss, loading and pending terrain edits
suppress the prompt. Windows remain static objects, not interactable hinges.
There is no new model scan, per-object timer or live icon viewport.

Validation on Godot 4.7.2 Windows x64:

- `building_interaction_hint`: graphical native scene check passed for open/close
  text, chest identity, intervening wall occlusion, changed aim between display
  and action, menu/loading exclusion and hiding after opening inventory.
- `door_world`: actual main-world HUD and E input open/close checks passed,
  including native compound hinge capture/restoration and exact closed pose.
- `door_component` and `bundle_structures`: existing headless checks passed.

Graphical runs used the repository launcher at 1920x1080 fullscreen, capped at
60 FPS. `door.png` is a minimal fixture layout capture, inspected for prompt
placement/readability; it is not a final-art screenshot. No human review,
frame-time or thermal improvement is claimed. Human save files were untouched.
