# Enclosed cottage integration — 2026-10-15

The prefab palette now contains **Furnished cottage with door and windows**,
appended after the existing built-in entries. Original cottage definitions are
unchanged. The new variant adds one hinged door and eight fitted glazed windows
to the existing table, chair, shelf and chest attachments. Placement uses the
existing complete prefab transaction and shared construction recipes.

`python tools/check_enclosed_cottage.py` clones `combined_gameplay` into a unique
`doors_*` slot, places the assembly, checks collision and E interaction, walks
the native player capsule through the open doorway and checks the interior aisle.
It saves through ordinary compound persistence and starts a fresh Godot process.
The reopened process verifies exact hinge state and door pose, eight window
identities and closing through ordinary E interaction. Source snapshot hash stayed
unchanged. First process: 14.25 seconds; second: 12.13 seconds. Both rendered at
1920x1080 with a 60 FPS cap; this is not a frame-time qualification.

The assembly is deliberately elevated in the disposable clone to isolate building
geometry from terrain preparation. The image is inspected assembly evidence, not
a finished grounded scene or a human-playtest checkpoint. Windows fit their
openings; their frames are recessed into the existing thick block walls. Final
building art, a prepared-ground review area and furnished tower are still pending.

Retained fixture failures: a horizontal test_move probe touched the floor (upward
normal); replaced with actual capsule walking. The first reopen aim was inside the
wall thickness; moved into the interior aisle. No collision/render code changed
to make either check pass. Startup receive hitches remain visible in the logs.
