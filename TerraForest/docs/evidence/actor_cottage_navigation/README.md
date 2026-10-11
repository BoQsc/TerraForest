# Cottage stair traversal and player support — 2026-10-11

The unchanged `brick_cottage.tres` exposed a real actor route failure: the initial
planner could not reach its raised floor via quarter-metre stairs and a one-metre
wide doorway. `baseline.log/json/png` retain that failure. A diagnostic capsule
probe (`stair_probe.log`) showed that tread-centre height alone does not give the
capsule clearance around riser corners.

Native local planning now samples intermediate treads, verifies <=0.30 m risers and
checks capsule clearance with a bounded fallback. The same actor body now performs
collision-checked up/forward/landing steps, including headroom and support. Readiness
bounds cover the additional vertical sweep and support-ray extent. The normal flat
edge remains four physics queries; stair fallback is capped at 24 queries per edge,
within the existing shared twelve-unit/cooperative 750us scheduler. The deadline can
be exceeded by an individual bounded unit; it is not a hard real-time guarantee.

The user raised player stairs as a concern, then clarified there was no observed
player failure yet. The production player motor and controller capsule settings did
pass walk/run at 60 physics ticks, but a targeted test reproduced stalls at 120 ticks
and slower 2.5 m/s movement. `player_baseline.log` retains those failures. Capsule/riser
contact intermittently loses the floor flag after a valid step. Both native motors
now retain verified support for exactly the next engine physics tick. The player latch
is also tied to body identity. Step height stays 0.30 m; upward/jump velocity rejects
stepping. This does not grant free airborne climbing or bypass swept collision.

Passing evidence:

- `player.log`: walk 5.5 m/s and run 9.9 m/s at 60 and 120 physics ticks, 2.5 m/s at
  60 ticks, a one-metre obstacle remains unclimbable, and a low ceiling blocks ascent.
- `movement.log`, `ladder.log`: existing velocity/swimming and ladder regression suites.
- `contract.log`, `collision.log`: existing blocked/edit/unavailable/activation bounds
  and authored-structure collision regressions.
- `cottage.log`: actual native prefab collision/rendering and actor-world adapter;
  six checks pass, including the cottage interior destination and clear-route control.
  `result.json` retains trajectories and scoped costs. The final actor route was ready
  after about 0.32 simulated seconds; measured planning peak was 927us and total adapter
  peak about 1.95ms in this two-actor fixture. These are observations, not release gates.
- `route.png` and `entrance.png`: 1920x1080 fullscreen rendered evidence, 60 FPS cap.
  The entrance image visibly shows the actor inside the original doorway.

Debug/release player and world DLLs rebuilt with pinned Zig/prebuilt godot-cpp; the
retained tests exercise debug. `manifest.json` records test/engine/binary identities.
The collision regression predates only the final enlargement of planner readiness
bounds; the route contract and cottage run use the final world binary.

Scope: real authored cottage geometry, native motors and bounded actor orchestration.
The player fixture reproduces production body settings but does not exercise main-world
input, terrain streaming or full settlements. No user-playtest acceptance, arbitrary
stair guarantee, crowd performance or thermal qualification is inferred. Saved-order
reload, a furnished-settlement route and simultaneous planning latency remain next gates.
The actor plans use the original destination; no hand-authored route bypass was added.

Reproduce:

```
python tools/run_godot_check.py player_cottage_stairs --headless --timeout 35 --require "failures=0"
python tools/run_godot_check.py actor_cottage_navigation --timeout 25 --require "failures=0"
python tools/run_godot_check.py actor_route_contract --headless --timeout 25 --require "failures=0"
```
