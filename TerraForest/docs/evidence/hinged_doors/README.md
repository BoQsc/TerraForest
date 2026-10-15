# Hinged doors — 2026-10-15

Wooden doors are available in the normal object palette and prefab recipes.
Aim and press E to switch between closed and a 90-degree open pose. The model
keeps its identity, so ordinary object damage continues across opening/closing.
The existing bounded native batch owns rendering and nearby collision. A native
map stores closed poses only for open doors, bounded at 65,536 records, and is
registered in compound persistence as `door_hinges`. No per-door update loop.

The component test checks actual collision before/after opening and closing,
player swing rejection without mutation, native state/model restoration, 100
round trips without drift, malformed snapshot rejection, missing identities,
rotated hinges and safe rebasing after an editor move. The main-world test uses
the ordinary E input, checks dirty state, compound capture registration, restore
and subsequent closing. Both native debug and release extensions built against
the existing prebuilt godot-cpp SDK.

Commands:

- `python tools/run_godot_check.py door_component --headless --timeout 30 --require "DOOR_COMPONENT failures=0"`
- `python tools/run_godot_check.py door_world --timeout 65 --require "COMBINED_RESOURCE_ROUTE failures=0"`

The world run is a disposable 1920x1080 rendered world. Its inherited final
"ordinary compound save completes" message only checks successful shutdown;
the log explicitly says saving was skipped. Disk restart is **not** proven.
The initial test used the save wrapper instead of its `sections` field, causing
a fixture failure; that log is retained.

Pending: furnished-building placement and visual review; actual disk restart;
door animation, locks, actor/static obstacle swing checks and actor door-opening
behaviour. Current swing protection covers the player only. Current doors switch
pose immediately; they are not physical swinging rigid bodies. Model collision
rebuild follows the existing bounded nearby collider queue.
