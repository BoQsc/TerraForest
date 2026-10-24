# Held-tool impact timing

2026-10-24. Mouse-down previously applied damage immediately, repeating every
250 ms while the 1.2-second pickaxe animation refused to restart. Gameplay now
starts an identified swing, resolves one live target at its visible contact pose,
then waits for that animation's recovery. Damage, target feedback, destruction,
salvage and native tool wear use the existing accounting path at contact.

The actual AnimationPlayer timeline owns skinned-tool timing, including playback
speed changes. A frame that crosses contact advances to that pose before emitting
the event, so a long frame cannot skip its presentation. Hammer and assembly
previews emit contact at their existing Tween's forward endpoint. There is no
separate periodic damage timer. The 250 ms minimum input debounce remains below
the actual swing/recovery durations.

| Current animation | Contact | Full clip |
| --- | --- | --- |
| Selected pickaxe pullback | frame 32 / 60 fps | 1.2 s |
| Optional diagonal pickaxe | frame 32 / 60 fps | 1.2 s |
| Legacy pickaxe | frame 41 / 60 fps | 1.3 s |
| Hatchet | frame 34 / 60 fps | 1.1 s |
| Empty hands, existing relaxed reach | frame 13 / 30 fps | 0.9 s |
| Building hammer / assembly preview | 0.1 s | 0.28 s |

Pickaxe frame 32 retains the authored contact marker and liked animation keys.
The retained calibrated-mesh probes evaluate the sharpened point using the actual
runtime skin binds: the selected pullback tip is approximately (0.140, -0.010,
-0.995) m in camera space there. The axe passes aim height around frame 34;
the legacy pickaxe between frames 40 and 42. No rig, mesh or authored key changes
were made. Empty hands had no swing clip; they reuse the existing deliberate
reach, rather than applying invisible damage. This is not newly authored punch art.

The world host validates active identity, equipment/slot ownership, focus, world
epoch and readiness, menus and live reach/occlusion before mutation. An early
callback cannot authorize damage. Equipping, inventory, Session, Alt, focus loss
and reload cancel pending contact. Successful mining can finish its recovery
while the accepted native terrain edit publishes. Misses and protected targets
consume no wear. Existing damage values, 3.5 m query reach and native save formats
are retained; this does not introduce physical tool-mesh collision.

## Verification

Passing run manifests and console/engine logs are retained in the named folders.
All world checks use disposable temporary worlds and fresh derived-cache paths.

- `animation_timing`: 24 checks covering exact contact, no windup hit, full
  recovery, long-frame contact pose, slower playback, equipment cancellation,
  hands/axe profiles and both procedural previews.
- `contact_world`: 44 actual-world checks covering single-click release, early
  callback rejection, repeated input, native damage/wear, retargeting, out-of-reach
  misses, all cancellation routes, native ownership moved without HUD refresh,
  actual reload and held input with the host physics and standing collision active.
  Three held swings produced three contacts, 90 damage and three wear points.
- `world_damage`: 83 checks for all supported tool/target families, destruction,
  native wear, container protection, feedback, terrain density publication and
  contextual HUD input. Terrain assertions now inspect the published native
  density revision after recovery, instead of requiring an edit to stay pending.
- `character_world`: 20 checks including fitted zombie hit regions and the actual
  held axe's block damage/destruction route.
- `tool_replacement`: 19 checks including break at contact, automatic empty hands,
  gathering/crafting a replacement, equipping it, native wear and snapshot restore.
- `building_salvage`: 34 checks covering protected parts, exact salvage, paid
  fence placement, native wear and prevention of duplicate salvage.
- `unified_tools`: 51 checks for existing inventory/belt/menu/construction and
  actual terrain/empty-hand attack routes.
- `human_placement`: 42 checks for the existing placement gesture, locomotion,
  actual editor fill acceptance/publication and return to idle.
- `character_runtime`: 31 checks for imported human clips and existing encounter,
  collision/occlusion, zombie anatomy and suspension behavior.
- `pickaxe_preservation`: 9 checks compare all 59 bones, grip stations, body and
  unchanged contact/recovery against the retained approved side-swing version.
- `native_durability`: 21 checks for sparse native damage accounting, capacity,
  serialization and invalid-save rejection.

`packed_runtime` runs the same 44 actual-world contact assertions using an external
test script with the exported PCK as res:// and dist as the project root. Its
manifest records the command and PCK/engine/native hashes. Tests are excluded
from the PCK; screenshots write to an explicit writable report directory.
The export and startup smoke logs are retained separately. These are finite
functional checks on this machine, not clean-machine installation or sustained
performance qualification.

The source windup/contact/recovered 1920x1080 captures were inspected: no target
feedback in windup; 90 / 120 at contact; no second damage during recovery. Captures
use the actual runtime rig and world. They do not establish physical reach to
the fixture block or human acceptance of strike feel.

```powershell
python tools/run_godot_check.py attack_animation_timing --timeout 40 --require 'failures=0' --headless
python tools/run_godot_check.py attack_contact_world --timeout 110 --require 'failures=0' -- --gameplay-construction
python tools/run_godot_check.py world_attack --timeout 150 --require 'failures=0' -- --gameplay-construction --ground-cover
python tools/run_godot_check.py unified_tools --timeout 100 --require 'failures=0' -- --gameplay-construction
python tools/run_godot_check.py character_runtime --timeout 40 --require 'CHARACTER_RUNTIME_OK' --headless
```

## Retained failed checks

- The initial clip probe assumed an unarmed Swing existed and errored. Inspection
  found no such clip; the existing relaxed reach now supplies visible timing.
  That diagnostic output is retained under `retained_failures/initial_probe`.
- The first world fixture used unqualified SceneTree focus constants and did not
  parse. It now uses Node's window-focus notifications (`parse_focus`).
- The next fixture passed its single-hit/cancellation checks but disabled physics,
  so held input could not repeat (`held_without_physics`). The next attempt
  enabled physics but retained reload's floor-spawn flag, moving its aim away
  from the target (`held_floor_spawn`). The final fixture uses real standing
  collision, clears the test spawn flag and runs actual host physics.
- Four old terrain assertions required a transient pending edit after full swing
  recovery (`terrain_pending`). They now verify the actual density publication;
  the revised 83-check route passes.
- One character-runtime invocation required the wrong completion string
  (`character_completion_token`). Its assertions passed, but the launcher failed
  it; rerunning with CHARACTER_RUNTIME_OK passes both checks and launcher.

The modified natural/regional ore, geology-reward and broad item-flow fixtures
also await real swing completion instead of immediate mouse-down damage. Those
extended routes were not rerun for this timing patch; they are not included in
the passing counts above. Generator/storage/mining latency and broader world
acceptance remain tracked in WORLD_FOUNDATION_STATUS.md.
