# Native vehicle runtime

0BSD port of the user's Vehicle Driving Test policy. NativeDrivingPolicy owns
steering command smoothing, speed-dependent authority and cap recovery, and
longitudinal acceleration/braking including the turn-grip budget. One policy
instance belongs to one vehicle. reset() resets steering state after landing,
impact recovery or vehicle reset. steering() returns angle/cap/fraction;
speed() returns speed/acceleration. Inputs use metres, seconds and radians.

Build: `python tools/build_native.py --addon vehicle_runtime --target all`.
Uses the pinned Zig/prebuilt godot-cpp workflow; see its separate MIT notice.

The vehicle_demo adapter retains original suspension, rigid-body integration,
visual effects and interaction scripts pending migration. Neither the policy
nor demo provides streamed collision readiness, vehicle persistence, authority
or fleet activation/LOD. The simple CharacterBody controller was discarded
before integration in favour of preserving the supplied vehicle behavior.
