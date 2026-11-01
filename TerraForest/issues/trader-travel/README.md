# Trader rides between settlements

- Status: In progress / verified inert native foundation; no playable paid ride yet.
- Updated: 2026-11-01. Requested: destination selection, both occupants travelling
  by car on roads, and trader returning after the player gets out.
- User review: Not reviewed. No visual/gameplay acceptance claimed.

## Changes and verification

Native published-road graph, road-distance quotes, heading-constrained departure
and bounded controls pass 27 debug and 27 release assertions. The optional
vehicle callback is unset in normal play and retains the existing native chassis
integrator. The actual-car fixture passes nine checks: ordinary W/A/handbrake,
two autonomous corners, stopped arrival and hold while S/R keys are pressed.
Maximum centre-line deviation is 2.006 m; this is not a complete chassis-clearance
claim. Existing policy parity (3,600 samples) and motion parity (240) also pass.

Exact sources, hashes, scope and retained outcomes:
[verification record](verification.json), [physical report](logs/physical_final.json),
[physical log](logs/physical_final.log), [debug](logs/native_debug.log) and
[release](logs/native_release.log). No production paid service is enabled.

Initial graph test: 18 assertions passed in
`reports/checks/20261101T163427413803Z/engine.log`.
The first physical fixture [failed four of five assertions](logs/physical_initial_failure.log):
the follower retained the old segment while rounding a corner. It now switches
when the adjacent segment is closer. A later fixed two-second player-brake
[fixture assertion failed](logs/player_brake_fixture_failure.log); using the
existing bounded eight-second braking convention passes at 0.06756 m/s, with no
production braking changes. Original runs remain in
`reports/checks/20261101T163642775038Z/` and `20261101T164241440094Z/`.
Fixture results do not establish production-world travel or performance.

## Images

No player-facing images yet. The shared rendered-test window was owned by the
clothing world check. No visual success is claimed from headless tests.

## Remaining / resume here

Exact flow, dependencies and closure evidence:
[travel contract](../../docs/TRADER_TRAVEL.md). Boarding, passenger control,
atomic payment, safe exits, persistent service identity and independent distant
return residency remain unimplemented. Coordinate trader UI with quest work.
Do not expose payment before the service can finish a trip and recover failures.

## Reproduce

Run `python tools/check_trader_ride.py` and again with `--release` for isolated
debug/release native checks. Alternatively use
`tools/run_godot_check.py trader_road_journey --headless --timeout 60
--require "TRADER_ROAD_JOURNEY checks="` for graph/control contracts and
`tools/run_godot_check.py trader_ride_physics --headless --timeout 90
--require "TRADER_RIDE_PHYSICS checks="` for the real chassis on an isolated flat
road fixture. These checks do not touch player saves.

New code/tests are original AI-assisted 0BSD work for this request. Existing car
code/visuals retain their notices; no imported assets or new license exception.
