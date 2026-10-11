# Native local actor routes — 2026-10-11

The original six-second wall-route failure is resolved. The actual actor-world adapter,
native activation/movement and batched visuals now reach both the clear destination
and the destination behind the authored-layer wall. Six assertions pass. Goal markers
are visual-only (collision layer zero), removing an unintended raised obstacle in
both control/detour paths; the wall collision and arrival assertions are unchanged.
The original failing evidence remains in `../actor_navigation`.

Fourteen native contract checks pass for planning, a newly inserted wall, replanning
and arrival, leaving/returning, unavailable collision and position hold, search limits,
a sealed enclosure, avoiding endless blocked retries, reopening a route, and work/node
bounds. The structure-collision and existing activation suites pass. Six main-world
wiring checks pass, including terrain/structure/lake signals and suspension. The world
wiring fixture is not a settlement route or population benchmark.

Both native binaries were rebuilt with pinned Zig/prebuilt godot-cpp; no godot-cpp
sources were rebuilt. These runs exercise the debug DLL. `manifest.json` retains
engine/test/binary identities and wrapper results. Graphical output is 1920x1080
fullscreen with a 60 FPS cap; `route.png` is the final frame, `result.json` includes
trajectories and scoped timings. Short CPU observations are not GPU/thermal or sustained
60 FPS evidence.

Implementation: local native incremental A*, 0.5 m cells, 2,048 nodes per active proxy,
+/-16 m horizontal extent, twelve shared work units per tick and a cooperative 750us
planning deadline. Capsule sweeps and support rays constrain edges; collision readiness
is checked before querying. Unknown coverage is distinct from an exhausted local graph.
The main world adds dry-ground admission. Orders remain authoritative saved state;
route searches are disposable. Selected-actor HUD exposes route status, with commands
available in the existing Development menu. See the addon README for API/limits.

Still open: an actual furnished-settlement route and doorway widths, representative
terrain slopes, saved-order reload with routes, multiple simultaneous planning latency,
crowd/dynamic obstacle avoidance, stair/multistorey traversal and regional long-distance
routing. Grid failure is not proof that no continuous route exists. This closes the
small obstacle-route gate, not M3 or the whole actor-navigation slice. Existing cadence
and population benchmarks predate planning latency; rerun with planning latency measured
separately from steady movement before making population/cadence claims.

Reproduce:

```
python tools/run_godot_check.py actor_route_contract --headless --timeout 30 --require "failures=0"
python tools/run_godot_check.py actor_navigation_world --headless --timeout 35 --require "failures=0" -- --actors
python tools/run_godot_check.py actor_navigation --timeout 20 --require "failures=0"
```
