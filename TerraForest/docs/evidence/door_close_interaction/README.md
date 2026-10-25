# Close/blocked-player door use — 2026-10-25

The player interaction adapter previously passed the player's 0.68 x 1.8 x
0.68 metre guard bounds into the native swing veto. E now supplies no player
protection bounds. The native actor/zombie/ragdoll/vehicle occupancy checks,
leaf collision, identity, hinge transform and storage format are unchanged.

`NativeBlockWorld.raycast_scene` gains an optional `hit_from_inside` argument,
default false. Only the shared E/hint query and standalone door adapter opt in.
A camera inside a leaf can therefore identify that door at zero distance,
rather than seeing through it or losing the prompt. The three-metre segment,
player RID exclusion, authoritative block occlusion and nearest-hit ordering
are unchanged. This adds no second ray or collection scan to the interaction
loop, and does not change targeting for mining, placement or weapons.

## Verification

- `component`: existing native hinge tests pass, including occupied swings for
  actor/vehicle/zombie/ragdoll layers, exact restore/close, 100 no-drift cycles,
  malformed state rejection, moved/rotated doors and explicit protected bounds.
- `ray_debug` and `release_comparison/release_door_scene_ray`: 12/12 scene query
  checks pass, including existing masks, exclusions and block occlusion plus
  inside-origin picking and unchanged default behavior.
- `world_source`: real main-world HUD/E input passes near-contact on either
  side, standing within the swing, camera inside each leaf orientation, closure
  across the player's capsule and escape using normal native movement. Existing
  hinge/model snapshot restoration and dirty marking also pass. The fixture
  suspends the host for exact placement, not the physics server or leaf collision.
- `package`: final PCK runs the expanded real-world test, additionally verifying
  unchanged use range and intervening-wall occlusion from outside and inside the
  wall. Only the test helper import changes to an absolute local path because
  tests are intentionally excluded from the exported pack. Its actual command,
  source hash, pack hash and all 14 native-library hashes are retained. The
  fixture uses a unique temporary world; it never saves over a player world.
- Both native structures targets build. The exported PCK and external libraries
  pass startup; the existing unrelated item-icon bake manifest is unchanged.

## Known broad-suite failure

`structures_debug` reports 18 failures in legacy prefab/invalid-shape assertions.
The clean `release_comparison/baseline_structures` fixture uses the original
HEAD (`9be30fcf`) structures test and release DLL, not a modified approximation:
it also fails those 18 assertions. The current isolated release suite retains
the same failures while all three new assertions pass. The comparison manifest
records equal diagnostics. This task does not edit those unrelated expectations
or claim the entire structures suite passes. Audit the shape catalogue/fixture
contract separately. The first broad debug invocation also requested an old
textual completion marker; the later comparison uses the actual STRUCTURES_RESULT
marker and independently retains the same assertion failures.

## Reproduce

Build: `python tools/build_native.py --addon structures --target all`.
Use `tools/run_godot_check.py door_component --headless --require
"DOOR_COMPONENT failures=0"`, and the same runner with `door_scene_ray` and
`--require "failures=0"`. For `door_world`, use the full command in the source
manifest (normal rendered gameplay, seed 1703/profile 21). Exact isolated release
and packaged commands and hashes are retained beside their logs. Re-export with
`tools/export_pack.py` when changing native libraries or the interaction scripts.
