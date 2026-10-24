# Developer vehicle spawning

## First-click correction, 2026-10-24

The previous implementation still required entering development mode before the
vehicle button would act. Its fixture explicitly expected that rejection, which
missed the user's actual first-click workflow. The user reproduced failure again;
the earlier successful records below do not qualify the corrected requirement.

Both the main spawn button and **Drivable vehicle · 501** now call a direct
vehicle request in ordinary gameplay. There is no aim, mode, focus, terrain
publication, slope or full-footprint admission gate for this action. A few native
ground/clearance queries prefer a nearby open pose, but failure to find one falls
back to a frozen vehicle in front of the player. This force-spawn action can
intersect scenery in an enclosed area; it does not alter terrain or delete trees
to make room. Driving retains its existing collision-readiness policy. A full
live-body pool parks another vehicle while preserving its record. Normal carried
vehicle-item placement is unchanged. Only a genuine model/storage creation error
can fail the request. Loading waits on the original click, with no ten-second
retry deadline or duplicate-click creation.

At the user's request, verification was limited to one focused exported-game
run: [first-click result](first_click/console.log), [manifest](first_click/run.json).
Its seven assertions cover ordinary gameplay, sky aim, an ordinary interaction
callback deliberately returning unavailable, a visible frozen body from one click,
unchanged gameplay mode and the vehicle item-list button's first click as well.
The [capture](first_click/nearby_vehicle.png) was inspected. The updated exported
pack and native libraries are installed in dist. Older source/lifecycle/package
records below describe the superseded placement-gated behavior and remain retained.

## Earlier placement-gated implementation

2026-10-24. The Escape Developer button required the centre camera ray to hit
level ground within twelve metres, then closed the menu and only showed a brief
world notice on rejection. Looking straight ahead could miss ground entirely.
The first fleet placement could also report success after creating a record
without immediately admitting a visible vehicle.

The button now reads **Spawn drivable vehicle nearby**. It checks up to nine
visible positions ahead at 5, 7 and 9 m, with 0/+3/-3 m side offsets, and accepts
the first ready, supported and unobstructed footprint. Line-of-sight and native
physics queries reject space behind obstacles. The full rotated footprint's
conservative world rectangle receives a fixed nine-point native block-world
support survey; standalone addon hosts use nine engine physics rays instead.
Missing or excessive uneven support rejects. Player clearance, world collision,
saved-vehicle occupancy and fleet-capacity rules remain enforced. Paid carried
vehicles retain aimed placement and share the support check.

A first fleet spawn now immediately admits its live body before reporting
success. Failed admission rolls back the new record. The Developer button waits
up to ten seconds for an in-flight model request, disables duplicate clicks and
rechecks ordinary interaction/development permission. Rejection keeps the
Developer page open with the reason at the bottom. Gameplay mode receives a
visible explanation of how to enter development mode. Successful spawning closes
the menu and shows the actual vehicle. Item payment, saved damage, driving,
parked stance height and save formats retain their existing behavior.

Verification:

| Check | Evidence |
| --- | --- |
| Real forest, actual menu signal, level camera; 9 assertions | [source](source/console.log) |
| Standalone placement, entry, immediate moving exit, persistence/reuse, unsupported ledge rejection | [lifecycle](lifecycle/console.log) |
| Same 9 menu assertions against exported game | [packaged](packaged/console.log) |
| Export and fourteen-library startup | [build](build) |

The real menu fixture verifies development-mode gating, waiting for the resource,
one-click placement with a level camera, immediate live visibility, bounded player
distance, readable rejection without an extra fleet record and small-ledge
rejection. The standalone lifecycle fixture additionally supplies loaded geometry
with a tiny high ledge and requires the missing-support rejection reason, no live
car and no saved record; this isolates footprint admission from readiness.
Source and packaged vehicle/failure screenshots were inspected in [images](images).
These are bounded correctness checks, not a whole-world placement or frame-time
qualification. No existing save was modified; fixtures use temporary worlds.

The first source attempts failed on an untyped physics-space local in the new
helper, causing dependent scripts to fail compilation. The local is now explicitly
typed; both failed logs/manifests remain in [failures](failures). Final logs contain
no script/runtime errors. Godot-generated UID sidecars accompany the helper/test.

Reproduce from TerraForest:

```powershell
python tools/run_godot_check.py developer_vehicle_spawn --timeout 100 --require 'failures=0' -- --gameplay-construction --vehicle-fleet --no-zombies
python tools/run_godot_check.py world_vehicle --headless --timeout 45 --require 'failures=0'
python tools/export_pack.py --godot 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot Engine.exe'
python docs/evidence/developer_vehicle_spawn/check_pack.py
```

Run the packaged check after export finishes. Its external assertion driver uses
game scripts/assets from PCK/dist; its manifest records engine, driver, package and
all fourteen native-library hashes.
