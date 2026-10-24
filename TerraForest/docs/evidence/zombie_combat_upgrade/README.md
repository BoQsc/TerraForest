# Zombie combat upgrade

2026-10-24. Player weapon contact now uses the real animated R4 skin rather than
the broad movement capsule or hulls fitted to an earlier pose. The native query
caches imported vertex/index/skin/morph data once, evaluates the current skeleton
and active blend shapes on demand, and intersects the visible attached parts.
The world query still respects intervening solid geometry. Physical corpse poses
remain hittable even after the body moves away from its retired character root.
Cosmetic wound-cap geometry is not a separate damage pool. Detached pieces remain
physical obstacles; they do not grant another living target or resource drop.

Native anatomy owns fourteen limb pools and 180 body vitality. Arm damage weighs
0.35 toward vitality, leg damage 0.45, torso damage 1 and head damage 1.75.
Severing hits now also affect vitality; exhausting a head is fatal even if body
vitality remains. Death clamps health to zero. Missing parts, invalid/nonfinite
damage and duplicate detachment cannot mutate state. Wounds in any section of an
arm reduce its effectiveness. Combat feedback displays limb and overall health
together, with tool wear and damage applied once at the held animation's contact.

All thirteen sever roots retain the existing descendant removal, cut caps,
detached jointed chains and collider masks. Leg loss transitions to a living
crawler; one intact arm can crawl more slowly, no intact arms leave a stationary
crawl bite, and unavailable arms cannot authorize impossible attacks. Corpse
hits can sever more parts without reviving it. Authored jump/climb action code
and the native navigation profile restrictions remain in place.

Roaming increases from 0.45 to 0.72 m/s, healthy pursuit to 0.864 m/s, and healthy
crawl from 0.32 to 0.4 m/s. The existing gait remains driven by measured travel.
Initial/engaged sight is 32/44 m, with a 140-degree initial cone and 5 m close
visibility eligibility. Sight refresh is bounded to two residents per host tick,
normally every 0.15 s per resident. Walking/running can leave an investigation
clue within 7/12 m; hearing does not authorize attack or continuously track a
hidden player. Occlusion, eighteen-second last-seen expiry, search, disengagement
and blocked-target cooldown remain enforced. Existing spawn distance 40–64 m and
eighteen-second initial grace are unchanged.

The corpse problem reproduced with animation off and all spring/motor flags
false: joint/contact corrections kept bodies awake, particularly at forest world
coordinates. Native physical-bone and rigid-part subclasses now stabilize only a
verified quiet supported island in their own normal physics callback. Native
contact checks run at 10 Hz. Passive damping starts after support; after 0.9 s of
quiet the joint constraints are parked and bodies sleep. Real impacts, damage,
support loss and nearby world edits restore constraints and gravity. Detached
joint frames restore relative to their current second body, not the original
standing position. Airborne bodies never freeze on a timeout. Sleeping fragments
that stop reporting contacts receive one short support ray per island, bounded
by sixteen tracked groups, so later scattered islands cannot be starved. Resting
rigid fragments temporarily park CCD and default force integration; their collision
impulses and normal motion integration remain available. Wake restores the original
CCD/force settings, and support-removal checks require them to fall again.

The native cache bounds are fourteen parts, 256 skeleton bones, eight surfaces
per part, eight skin influences and sixteen morphs per surface, with 131,072 total
vertices/triangles. Each anatomy tracks at most sixteen groups of sixteen bodies
through weak object identities. The supplied rig is well below those limits.
There is no GPU readback, extra walking proxy or second body integrator. This is
bounded correctness evidence, not an aggregate CPU/GPU/frame-time qualification.
The six-resident encounter limit remains. Encounter anatomy stays session-local;
world save formats and existing saves are unchanged.

Character Preview.cmd was a redundant temporary-world shortcut. Its removal is
recorded separately in commit `2cc75b37`; Worlds.cmd remains the documented normal
launcher, and developer command-line arguments remain available.

Verification records are linked below. Each retained run manifest records the
source revision and dirty worktree, engine/test/native hashes where supplied by
its runner. Older regressions precede the final corpse-displacement/support-budget
refinement; final rig/release/package checks exercise that refinement. No source
or gameplay assertion failures are treated as acceptance.

| Check | Record | Assertions |
| --- | --- | ---: |
| Native health source | [health_source](health_source/console.log) | 16 |
| Awareness source | [awareness_source](awareness_source/console.log) | 31 |
| Real forest player swings and corpse | [forest_source](forest_source/console.log) | 26 |
| Final source animated rig and physical parts (headless) | [regions_source](regions_source/console.log) | 39 |
| Earlier rendered source rig | [regions_rendered](regions_rendered/console.log) | 38 |
| Clean imported rig, release DLLs only | [regions_release](regions_release/console.log) | 39 |
| Native health release | [health_release](health_release/console.log) | 16 |
| Native awareness release | [awareness_release](awareness_release/console.log) | 31 |
| Actual host awareness/roaming/search | [behavior](behavior/console.log) | 21 |
| Supported navigation | [navigation](navigation/console.log) | 14 |
| Travel-driven gait | [gait](gait/console.log) | 24 |
| Six-zombie crowd and crawl attacks | [encounters](encounters/console.log) | 17 |
| Real forest zombie attacks and Escape suspension | [world_combat](world_combat/console.log) | 9 |
| Door attack and structural accounting | [doors](doors/console.log) | 14 |
| Packaged player combat and forest corpse | [packaged_world](packaged_world/console.log) | 26 |
| Packaged rig and physical parts | [packaged_regions](packaged_regions/console.log) | 39 |

The rig check compares native hits against independently baked skin in idle,
both-arm attack, dragging walk, crawl, bite and crawl-bite poses. It requires all
fourteen regions across those poses, rejects the empty leg gap, tests all thirteen
sever roots, and checks living crawl/attack restrictions. Physics checks cover
airborne gravity, model-floor collision, sleeping corpses, postmortem hits after
eight metres of displacement, new-impact wake and support removal. A six-sphere
fixture specifically tests ongoing support of six independent resting islands;
it seeds their rest flags after natural settling to exercise the contactless
sleeping-support path. Actual forest severed arm/head rest is tested separately
through three real player swings and the combat adapter. The forest player is
kept still for reproducible aiming; the separate world-combat fixture leaves the
normal host physics loop active.

Source and packaged captures were inspected for readable health feedback,
severed parts and collapsed corpses. See [source images](images/source) and
[packaged images](images/packaged). These isolated fixture images are not an
acceptance of district layout, terrain fit or whole-world navigation.
Build manifests, export and startup logs are retained in [build](build). The PCK
was unchanged by the final native-only corrections; updated debug/release DLLs were
copied to dist before the final packaged checks. Their exact hashes are recorded
in both package manifests.

Initial failures and diagnosis remain in [failures](failures) and [probes](probes):

- The baseline probe reproduced passive-joint chatter with drives already off.
  Direct sleep writes and a temporary joint-softening trial did not reliably
  settle the actual forest. Softening was reverted. Native rest callbacks,
  contact-island handling, contactless support checks and parking constraints
  resolved the real-world case. A later packaged run retained two awake bodies
  with tiny velocities after parking; a diagnostic confirmed explicit island
  sleep cleared them. Sleep is now committed after every island constraint has
  been parked. Further package runs still exposed a detached head renewing tiny
  contact corrections. CCD parking alone was insufficient; the final supported
  rest state also parks default gravity forces, restoring them on impact, edits
  or lost support. Finally, parked sleep is reasserted after scene/contact
  synchronization only for bodies that remain resting; meaningful impact flags
  restore dynamics first. The final package has all fifteen bodies asleep with
  zero velocities. These failed package runs remain retained.
- Initial dead-pose picking required mapping cached death skin through the live
  physical-bone ancestors. Some later corpse shots selected large face triangles
  pressed against the floor; the test now probes an exposed upper head surface
  while retaining world occlusion.
- The faster gait invalidated a historical fixed-speed fixture expectation; it
  now compares the actual configured travel/reference speed.
- The scattered-island fixture initially assumed its SceneTree callback would
  drive the helper, then incorrectly required the native rest flag before simple
  spheres had naturally slept. It now uses the physics-frame signal and explicitly
  seeds verified-rest state to test continued support. Actual unforced corpse
  settling remains a separate required assertion.
- Early native compilation failed on unavailable mesh/joint APIs; the final code
  uses the pinned SDK APIs. One final DLL installation overlapped an owned door
  regression process and hit a Windows file lock. After that process exited the
  same build installed successfully; no user game was terminated.

Reproduce from the TerraForest folder:

```powershell
python tools/build_native.py --addon world_runtime --target all
python tools/run_godot_check.py zombie_anatomy --headless --timeout 35 --require 'failures=0'
python tools/run_godot_check.py zombie_awareness --headless --timeout 35 --require 'failures=0'
python tools/run_godot_check.py zombie_combat_regions --timeout 90 --require 'failures=0'
python tools/run_godot_check.py zombie_combat_world --timeout 100 --require 'failures=0' -- --gameplay-construction --zombies
python docs/evidence/zombie_combat_upgrade/check_release.py
python tools/export_pack.py --godot 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot Engine.exe'
python docs/evidence/zombie_combat_upgrade/check_pack.py
python docs/evidence/zombie_combat_upgrade/check_pack.py --regions
```

Run export after tests finish, then packaged checks sequentially. Do not replace
native DLLs while a game/check holds them loaded. The release helper imports a
clean temporary project containing only the release world/player libraries and
actual rig assets. Package helpers use external assertion drivers while all game
scenes/scripts/assets resolve from PCK/dist, with package and native hashes.

Whole-world routes, automatic ladder/jump links, tight crawler clearance and other
open navigation gates remain under [NAVIGATION_STANDARD.md](../../NAVIGATION_STANDARD.md).
This milestone qualifies the combat/anatomy/perception changes and bounded physical
rest/wake cases above; it does not close those gates or the rejected district layout.
