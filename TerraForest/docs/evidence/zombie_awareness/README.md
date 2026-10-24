# Roaming zombies, awareness and distant spawning

2026-10-24. Normal gameplay now uses the existing session spawner with native
awareness instead of directing every admitted zombie at the player immediately.
This retains the original animated controller, one physical body/motor and the
shared native ActorRoute/NativeActorNavigator geometry and readiness contract.

## Current behavior

- **Unaware:** brief 1.5–4 second pauses between randomized 4–9 m wandering goals.
  Goals remain within the local home neighbourhood, are projected onto supported,
  dry, unoccupied ground and require a valid native route and guarded motion.
- **Notice:** a player within a 120-degree forward cone and 24 m requires actual
  solid-world line of sight and ready collision. Close awareness within 3.5 m
  still requires sight; walls never become proximity detection. Existing actors
  and fitted hit regions are not treated as static sight occluders.
- **Pursue:** engaged sight extends to 36 m and does not repeatedly lose a tracked
  player on small bearing changes. Actual melee retains the original authored
  windup/contact, live range/facing/occlusion and fitted-surface checks.
- **Investigate:** after losing sight, walk toward the last seen position. Hidden
  player motion cannot update it. Being struck provokes investigation even from
  behind. A remembered destination is not a player attack recipient.
- **Search/disengage:** reaching the last sighting selects a short local search
  goal for six seconds. Eighteen seconds without sight, or a blocked investigation,
  returns to wandering. A visibly unreachable chase also gives up after six
  seconds of blocked/search-limit state and ignores reacquisition for ten seconds.
  Unknown routes remain unavailable; there is no direct-chase fallback.

The host may select an existing authorized wooden-door target while chasing or
investigating. Perception uses the remembered goal for this approach. It cannot
grant generic wall destruction, free door opening, player salvage or tool wear.

`NativeZombieAwareness` retains at most six native intent records. The host
scaffolding supplies actual physics sight/support and routes; it does not own a
second movement simulation. Nominal sight cadence is four updates/second per
resident, staggered with at most two eligibility probes per physics tick.
Out-of-range/cone probes issue no sight ray. Melee clearance/contact geometry and
the existing route guards are additional work, not hidden in that sight budget.
Availability/ready gates freeze intent timers and physical bodies. Idle/corpse
agents do not run active searches. Native path budgets remain unchanged.

Automatic admission waits **18 active-play seconds** after startup/clear/pose
restore, then attempts one resident per **8 seconds**, at **40–64 m** horizontally
and outside the player's camera view. Four candidate probes, collision readiness,
dry ground, capsule occupancy and the combined six-live/corpse cap still apply.
Suspension and flight do not spend the spawn clock. Explicit `spawn_at` remains
available for development/test fixtures and can deliberately place close actors;
automatic gameplay admission owns the safe-distance policy.

`awareness_status`, the native status API, manager perception counters and each
body's behavior snapshot expose state, goal and timing for diagnosis. The
`force_pursuit` fixture flag defaults false and is not enabled by gameplay or a
launcher. Dedicated navigation/door/slope/regional fixtures use it to isolate an
already-acquired recipient from perception and memory; those tests do not count
as awareness coverage. The new behavior and world population checks use the
normal policy.

## Verification and visual review

Run manifests, console/engine logs, native build manifests, result snapshots and
inspected captures are retained in this folder. Native debug and release variants
were built together. Release awareness tests explicitly load the release DLL in
a clean temporary project. The exported-runtime check uses packed game resources
with an external assertion script and a writable screenshot path.

- `native_debug` / `native_release`: 27 intent checks for field of view, range,
  memory, no hidden-player tracking, search expiry, provocation, suspension,
  unreachable-pursuit cooldown, unsupported goals and bounded identity lifetime.
- `physical_behavior`: 21 actual-body checks for walking, noticing, pursuit,
  wall occlusion, last-seen investigation, suspension, reachable search, loss of
  interest, reacquisition, grace, offscreen/distant admission and reset. Traces
  distinguish intent, animation/body state and native route state.
- `population_world`: 9 normal-host checks establish no surprise startup spawn,
  camera exclusion, distant admission, unalerted state and real walking on
  streamed forest terrain. The admission cadence is accelerated in the fixture
  after the initial real three-second grace sample; the standalone scheduler
  check covers the full eighteen-second gate with bounded simulated updates.
- `crowd_combat`: 17 checks retain six-body spacing/contact, suspend/resume and
  living crawler attacks with perception enabled.
- `navigation`: 14 existing wall/water/stair, moved-goal, blocked/unavailable,
  invalidation and work/node-bound checks with an explicit acquired recipient.
- `world_combat`: 9 actual-host attack/contact and Escape suspend/resume checks
  with normal perception, not forced pursuit.
- `gait`: 24 existing evaluated-skin, foot-plant, blocked/resumed physical walking
  checks retain the weighted limp and body-travel-driven playback.
- `character_runtime`: 31 import/rig/anatomy/admission/contact/lifecycle checks.
- `actor_navigation`: 6 existing activation/route/body/collision checks.
- `door_interaction`: 14 actual-host wooden-door approach/contact/destruction,
  inventory/hinge isolation and continued traversal checks.
- `packed_behavior` / `packed_population`: repeat all 21 physical behavior and
  9 real-world population assertions against the exported game resources and
  native libraries. Their manifests record the pack/engine/test/native hashes.

The 1920x1080 forest capture shows the automatically admitted zombie walking on
terrain; the physical fixture captures show the actual imported rig in wandering,
chasing, investigation, search and disengaged phases. Traces and assertions prove
the transitions; a still frame alone does not prove awareness or a whole animation.
The initial wide-camera samples obscured the investigation body and made others
too small to inspect; they remain in retained_review. The final camera follows
the subject from its side of the wall and the corrected samples were inspected.
These are finite functional checks, not sustained CPU/frame-cost qualification,
human acceptance of encounter pacing or arbitrary-world navigation acceptance.

```powershell
python tools/build_native.py --addon world_runtime --target all
python tools/run_godot_check.py zombie_awareness --timeout 30 --require 'failures=0' --headless
python tools/test_native_release.py --godot 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot Engine.exe' --addon world_runtime --test zombie_awareness
python tools/run_godot_check.py zombie_behavior --timeout 90 --require 'failures=0'
python tools/run_godot_check.py zombie_population_world --timeout 100 --require 'failures=0' -- --gameplay-construction
python tools/run_godot_check.py zombie_world_combat --timeout 90 --require 'failures=0' -- --gameplay-construction --zombies
```

## Retained failed checks and remaining scope

The first clean-project release invocation omitted explicit extension loading,
so ClassDB could not instantiate the new class and the process timed out. The
fixture now loads the extension when absent and fails promptly if unavailable;
the release rerun passes. The failed engine log is retained as `release_loading`.

The character component fixture moved its recipient after its final manager
update and expected stale melee clearance to stay valid. It now updates the
manager during those contact frames, as the actual host does; the rerun passes.
The first actor-navigation invocation was headless although that fixture awaits
rendered frames unconditionally. It reached all six assertions and then timed
out; its rendered rerun passes. Both failed launcher manifests/logs are retained.

The first door regression exposed a real approach-distance mistake: measuring
arrival against a door approach point disabled routing about 1.55 m before the
leaf, beyond contact range. Routing now measures distance to the actual combat
recipient and retains the separate approach goal. The failed four-assertion run
remains visible; the corrected door check passes.

Encounters remain session-local and limited to six controllers, retiring beyond
96 m. Saved population/loot, player health/death/respawn, hearing/noise systems,
automatic jump/ladder links, arbitrary building/cave reachability and sustained
population performance are not completed here. Existing saved tower/cave journey
and slope fixtures now explicitly acquire a recipient; those extended routes were
not rerun for this behavior patch. Their prior qualified scope and open gates
remain in WORLD_FOUNDATION_STATUS.md and REGIONAL_NAVIGATION.md.
