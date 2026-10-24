# Optional third-person view

2026-10-24. **Escape → Session → Third-person camera** switches the on-foot view.
First person is the default. The choice is remembered in `user://player_view.cfg`
and does not change world-save formats. Offscreen generation/photo tasks ignore
the preference. The menu remains open while the checkbox changes the background
view; normal session input/cursor handling remains in charge.

One extra render camera follows Godot's native SpringArm3D at a shoulder offset,
up to 3.4 m behind the eye. A 22 cm sphere and 8 cm margin retract it before
terrain, models, vehicles and actors. Close retraction omits only player render
geometry through a dedicated visual layer; the existing held animation and contact
signals continue. The original eye camera remains the source of aim and reach.
One bounded native scene ray of at most 120 m aligns the third-person centre with
that eye target. Existing action queries still enforce their original shorter
reach and occlusion. The boom and per-frame aim update stop in first person;
driving suspends the on-foot view and its queries.

The existing R11 model and animation player are reused; no duplicate rig, actor,
collider or body integrator is introduced. Its body is aligned to the feet and
player yaw rather than pitching with the camera. Third person restores the head,
authored facial mesh visibility and body shadows, and allows existing locomotion
clips for unarmed movement. Switching back restores hidden head surfaces,
first-person tool transforms and shadow settings. Authored attack contact timing
is preserved. Visibility, canopy and underwater presentation use the active
render camera; the headlamp remains attached to the player's eye.

Vehicle entry transfers rendering back to the existing vehicle camera while
remembering the selected mode. Changing the checkbox in a vehicle cannot take
over its camera. Exit restores the selected on-foot view. World/player pose
capture retains its original feet/yaw/pitch semantics.

Verification:

| Check | Record | Assertions |
| --- | --- | ---: |
| Real forest and actual ESC checkbox | [source](source/console.log) | 21 |
| Authored attacks and cancellation | [attack_timing](attack_timing/console.log) | 24 |
| Existing vehicle lifecycle | [vehicle_lifecycle](vehicle_lifecycle/console.log) | 25 |
| Actual game from exported PCK/dist | [packaged](packaged/console.log) | 21 |

The integrated fixture checks default view, checkbox behavior with ESC open, stable
eye/player transforms, full upright model/head presentation, actual camera bindings,
screen-centre alignment to a nearby eye-ray target, rear/side wall retraction, near-camera
body culling, one held-tool contact during retraction, first-person restoration,
preference output and vehicle entry/change/exit. Tests use a temporary world,
disable the user's preference path and remove their separate PID-named test
preference file. Source and packaged [images](images) were inspected. These are
bounded functional/visual checks; they do not qualify all camera spaces or total
frame performance. Existing world-quality/navigation gates remain open.

The first fixture run had a GDScript inference error in a local boolean and did
not reach gameplay. The local is explicitly typed; the failed log/manifest remains
in [failures](failures). An initial packaged run passed its camera checks but
rejected the injected attack after capture. The fixture now explicitly supplies
the foreground input contract immediately before that attack; the exported game
code was unchanged. Both records are retained. The following source and packaged runs pass without
script/runtime diagnostics. Export/startup records are in [build](build).

Reproduce from TerraForest:

```powershell
python tools/run_godot_check.py third_person_view --timeout 100 --require 'failures=0' -- --gameplay-construction --vehicle-fleet --no-zombies
python tools/run_godot_check.py attack_animation_timing --headless --timeout 35 --require 'failures=0'
python tools/run_godot_check.py world_vehicle --headless --timeout 45 --require 'failures=0'
python tools/export_pack.py --godot 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot Engine.exe'
python docs/evidence/third_person_view/check_pack.py
```

Run the packaged helper after export finishes. Its assertion driver is external;
the cameras, menu, rig, native libraries and game scene resolve from PCK/dist.
The manifest records the engine, driver, pack and native hashes. Commit matching
Godot UID sidecars with the new module/test.
