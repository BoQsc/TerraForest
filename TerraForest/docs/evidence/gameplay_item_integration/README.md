# Terrain items, repair hammer and vehicle interaction

2026-10-24. Godot 4.7.2 / Windows x86-64 / Forward+ / RTX 4050 Laptop GPU.

## Behavior and ownership

- Equip topsoil (211), stone (201), iron (202) or copper (203); right mouse
  places the matching native terrain material. Native command 38 adds one
  lattice sample using an integer-centered radius of 0.75 m. It cannot create
  another negative sample or repaint existing solid material. The existing
  material/density binary storage and streamed mesh/collision publication apply.
  One unit is debited before the compound edit snapshot; a native no-op/rejection
  refunds through the saved reward inbox. Publication tickets prevent duplicate
  rewards; inbox receipts also account for refunds. Graceful shutdown waits for
  publication, and interrupted mutation protects the previous canonical save.
- Item 3 retains its save identity and is called **Repair hammer** everywhere.
  Left mouse uses the existing weapon attack. Right mouse restores up to 25
  structural durability to a block, object or vehicle at the visible contact
  marker, with live reach/ownership/readiness checks and one wear per successful
  repair. Full targets consume no wear. It has no construction preview/settings.
  Held building materials keep their existing paid construction controls.
- ESC / Session has a persistent, default-off targeting-outline option. The
  advisory native scene pick runs at most every 100 ms and never authorizes a
  mutation. It applies independently of the selected held tool/weapon.
- ESC / Developer has item-name/ID filtering, stack count, collectible item
  spawns and an actual drivable vehicle option. The catalog includes plants,
  resources, tools, clothing, bucket and vehicle. Free creation requires
  development mode. Five bounded candidate positions use support, readiness,
  occlusion and occupancy checks. Pickups remain native spatial records/batches.
- Vehicle item 501 is a singleton with a miniature world mesh and inventory
  icon. Native wear carries structural damage (maximum 300) across inventory,
  ordinary storage saves, drops, collection and deployment. Pickup exchanges
  one stable fleet identity for one item; deployment exchanges it back. Full
  inventory, stale selection, missing resources and blocked placement preserve
  ownership. Gameplay V no longer grants a free vehicle; development V remains.
- Tap E retains ordinary entry. Hold E for 350 ms opens **Enter vehicle** /
  **Pick up vehicle**. Move above/below the center, then release E or click;
  keys 1/2 also choose. Center, outside, right mouse and Esc cancel. Door,
  chest and loose-object interactions retain their priority. Action execution
  rechecks the selected identity, reach and obstruction. Holding the gesture
  cancels attacks and blocks editing; focus/menu/load changes cancel it.
- E exits without a speed gate. Five candidate exit capsules retain loaded
  geometry/occupancy validation. The player inherits current velocity and the
  vehicle retains its momentum with controls disabled. Coasting bodies stay
  within the existing four-body fleet budget and cannot be retired for another
  entry; they park after grounding and stopping. Native vehicle physics remains
  the sole motion owner. A moving vehicle must stop before **pickup**.

Cosmetic dents remain the pre-existing transient visual state; structural damage
is the saved/carried state. These functional checks do not establish large-scale
terraforming throughput, driving balance, total frame cost or human acceptance of
the repair/hold interaction feel. Camera readbacks and cold vehicle setup occur
in these captures: displayed FPS is not a performance baseline. Existing world
quality, navigation and endurance requirements remain in the main status file.

## Passed checks

Run manifests and console logs are retained under `runs/`, including failures.
All passing manifests require exit 0, no engine/script/FAIL diagnostics and the
specified completion witness.

| Check | Assertions / scope | Run |
| --- | --- | --- |
| Terrain material items | 24; four materials, one-unit recovery, material identity, binary roundtrip, native carried wear and bounded repair | `20261024T075622887051Z` |
| Clean release project | Same 24 assertions, only player/terrain release DLLs | `20261024T080753913306Z_items_release` |
| Mining rewards | 35; paid fill, unpaid rejection, no-op refund, re-mining, duplicate receipt, actual compound save/reopen, shutdown and saturation | `20261024T075622889069Z` |
| Gameplay items | 36; actual held soil/RMB, contact repairs, all-tool overlay, developer click/collection, E tap/hold, fast exit, radial pickup, stale/full rejection, vehicle storage/drop/deploy wear | `20261024T080329199545Z` |
| Packaged gameplay | 36; actual E-key fast exit retains player/vehicle velocity; game resources from PCK/dist, helpers external | `20261024T081603104985Z_gameplay_items_pack` |
| Inventory | 32; native transactions and current 520-byte snapshot schema | `20261024T075500456053Z` |
| Attack durability | 21; wear, transfer, native sparse damage and capacity | `20261024T075622885377Z` |
| Existing world attacks | 83; all held attacks, harvesting, damage and contact/accounting | `20261024T075450232282Z` |
| Bundled pickups | 100; every catalog mesh, physical transfer, stack contents and compound restore | `20261024T080100488163Z` |
| World vehicle | 24; moving exit, blocked geometry, camera/physics restoration, pose persistence | `20261024T080205578280Z` |
| Unified tools | 52; real menus/mouse, owned material construction, repair-hammer separation, inventory/chest, actual excavation | `20261024T080421973636Z` |
| Fleet native | Spatial selection, 10,000 distant records, snapshots and invalid requests | `20261024T080627975182Z` |
| Grass continuity | 20; actual paid brick/native mining and visible packets across edits | `20261024T080754872943Z` |

Both changed addons were rebuilt for debug and release with the pinned Zig/SDK;
their build manifests are adjacent. `export.log` / `pack_smoke.log` record export
and startup with fourteen external native DLLs. The final pack manifest records
the exact PCK/library/test hashes. Selected package UI captures were inspected
for readable text, fit, vehicle icon, radial choices and the placed terrain mound.

## Retained failures and corrections

- `075116…`: old inventory assertion expected 392 bytes after an earlier bucket
  schema migration. Corrected to the actual 520-byte format, then passed.
- `075118…` / `075206…`: world attack check launched without the actual
  `--gameplay-construction` flag (`--gameplay` has no effect). The valid gameplay
  launch passed 83 assertions.
- `075216…`: mining assertions passed, but the runner expected `failures=0`
  instead of its JSON `"failures":0` witness. The expanded check passes correctly.
- `075324…`, `075407…`, `075412…`: new SVG had not been imported yet, producing
  preload errors. Ordinary editor import/export generated its resource remap;
  subsequent source and packaged checks pass. The pickup check also exposed its
  old missing terrain-restore fixture, corrected to provide the current protocol.
- `075659…`: that fixture was initially assigned before provider registration,
  which correctly rejects registration after attachment. Assignment now occurs
  after setup; all 100 assertions pass.
- `075849…`: first developer pickup candidate was obstructed after soil placement.
  Five bounded clear-position attempts fixed actual click/spawn/collection.
- `080210…`: unified tool fixture assumed a bare terrain target while launched
  with plant picking enabled; the two terrain assertions instead hit cover.
  Its intended tools-only launch passes 52 assertions. The dedicated new world
  check exercises soil/vehicles with ground cover enabled; the existing attacks
  and continuity checks separately cover the populated interaction path.
- `080525…_gameplay_items_pack`: external helper inlining mixed space/tab
  indentation. The wrapper now normalizes the external assertion script;
  packaged game scripts were unchanged. Subsequent packaged checks pass.
- `080602…`: fleet assertions passed, but that older script has no `failures=0`
  console summary. Its actual final witness and exit status pass in `080627…`.

## Reproduction

From the project directory, use `python tools/run_godot_check.py <name>` with
`--require 'failures=0'` for the new native and gameplay checks. Mining and inventory
use the JSON witness `'"failures":0'`. Gameplay items need
`-- --gameplay-construction --ground-cover --vehicle-fleet --no-zombies`.
Native material assertions run headless. The normal vehicle, pickup and UI checks
render with Forward+; run those sequentially to retain focus.

Build with `python tools/build_native.py --addon player_runtime --target all`
and the same command for `volumetric_terrain`. Export using `tools/export_pack.py`
with the installed engine's `--godot` path, then run
`python docs/evidence/gameplay_item_integration/check_pack.py`. That wrapper uses
only external test helpers; `res://` game resources resolve from the pack.
Release verification uses a clean temporary project with both descriptors pointing
their debug/release features to the release DLLs, plus `mesh_codec.gd` and
`tests/terrain_material_items.gd`.
