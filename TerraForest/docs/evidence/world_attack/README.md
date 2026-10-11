# Unified world attacks, native durability and development HUD

2026-10-11. The integrated world fixture passes 53 checks. Native durability
passes 21 checks, including legacy inventory/container migration, worn-tool swaps,
atomic rejection, breakage, save validation and the 65,536-record capacity boundary.
Inventory presentation passes 24 checks and movement passes 27 checks.
Additional inventory, container, crafting and parked-vehicle regressions
are retained alongside their launch/build manifests. Full graphical checks use
1920x1080 fullscreen and a 60 FPS cap. Screenshots inspected. These short checks
are not sustained frame-time, thermal, multiplayer or older-laptop qualification.

## Behavior verified

- All four existing tools damage and excavate through one nearest-target route.
  Native block raycasting respects scene occlusion; ray reach is 3.5 m, cadence
  250 ms. Pickaxe favors stone, axe favors wood. Placeable stacks do not attack.
- Integrated fixtures exercise block damage/removal, pickaxe-to-axe shared tree
  damage, furniture salvage/protection, actors, vehicles, natural ground cover and
  excavation with each tool. Ground cover being republished rejects interaction
  before damage. Full containers cannot lose their contents through destruction.
- Tool wear moves through native inventory/container transactions and actual world
  drop/recollection. Tools break after 200 accepted hits. Replacement recipes use
  hand-gatherable stone and wood. Old inventory/chest formats load with zero wear.
- F1 toggles the persistent development panel; Alt exposes its mouse controls.
  Context changes with selected tool, inventory/menu focus hides it temporarily,
  and empty development slots do not inherit a terrain brush. Movement and belt
  switching regressions pass.

## Representation and limits

World damage is a native sparse ordered map keyed by stable target identities
(or coordinates for blocks/terrain). Untouched targets have implicit full health;
no per-target timers, bodies, nodes or update loop are introduced. A hit is
O(log damaged targets), and destroyed targets release their records. Snapshot
serialization is deterministic and bounded. At 65,536 damaged targets, new
records are refused explicitly without erasing old ones; existing records remain
usable. This is a bounded global store, not yet region-paged multiplayer state.
One run measured 1,000 native hits against 10,000 existing damage records in
3,114 microseconds; this narrow current-machine measurement is not a world FPS
or old-hardware comparison.

Inventory V2 uses 392 bytes for 32 slots (item, count, wear), versus V1's 264.
Container V2 records use 400 bytes plus the shared 16-byte header. Validators
accept both versions, reject malformed wear and stage restores atomically. Item
catalogs explicitly register maximum durability and single-item stack limits;
new tools/weapons need an attack profile and matching durable item registration.

Damage values are initial gameplay tuning. Terrain damage is per one-metre target
cell and submits the existing rounded-cut edit on destruction; it does not create
physics rubble. Water/sky are not solid health targets. Repair, damage-stage art,
structural collapse, armor balancing and multiplayer attack authorization are
outside this change. Successful edit submission is distinguished from long-run
mining/meshing performance; this change is not a new meshing algorithm.

The prebuilt godot-cpp SDK was reused for debug and release native builds, with
zero godot-cpp source rebuilds. New code remains 0BSD.

## Reproduction

```powershell
python tools/run_godot_check.py attack_durability --headless --timeout 20 --require 'failures=0'
python tools/run_godot_check.py world_attack --timeout 65 --require 'failures=0' -- --gameplay-construction --ground-cover
python tools/run_godot_check.py input_surface_regression --timeout 55 --require 'failures=0' -- --gameplay-construction
```

The input fixture pins its background cap to 60 after a prior run lost OS focus
and failed only its final cap assertion. The product retains its existing lower
idle cap. The parked-renderer fixture must run graphically because the headless
renderer does not preserve the transform readback used by its visual assertion.
