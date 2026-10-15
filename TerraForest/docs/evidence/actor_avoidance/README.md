# Active actor avoidance, 2026-10-15

M3 entity interaction coverage: two opposing actors previously intersected down
to 0.10 m centre separation. Active collision masks excluded other actors.
The native activation pool now enables engine RVO avoidance for its active
proxies and includes layer 8 in their collision masks. Existing route planning,
terrain readiness, authoritative positions and batched rendering remain in use.

Each proxy lazily creates one reusable NavigationAgent3D: radius 0.4 m, neighbour
range 4 m, maximum 16 neighbours, speed 2.5 m/s, 1 s agent horizon, ground-plane
avoidance. Normal world activation remains 16 bodies; hard pool cap remains 64.
Dormant store records create no agents. Sleeping proxies disable avoidance and
collision. Safe velocities are cached for at most two physics frames; missing
results hold horizontal movement. Corrections clear cached velocity. The engine
agent receives no path requests, so this does not introduce a second route planner.

Evidence:

- `overlap_before.log`: both destinations reached by walking through each other.
- `head_on.log`: exact opposing routes retain separation and both arrive.
- `crossing_release.log`: offset crossing passes, minimum separation 0.806 m.
- `world.log`, `world_motion.json`, `street.png`: both actors cross the actual
  furnished settlement street and arrive, minimum separation 0.800 m; shared
  route work remains at most 12 per update. Fullscreen 1920x1080, cap 60. A copy
  was used; source-save hash unchanged (`world_run.json`). Run with
  `python tools/run_actor_street_crossing.py`.
- `cottage.log`: existing raised cottage stairs and one-metre doorway still pass.
- `lifecycle.log`: sleeping disables avoidance, reactivation restores it,
  unavailable collision holds position; authored walls/floors still constrain it.
- `activation_release.log`: existing 100,000-dormant-record activation checks,
  invalid commands, restore and fixed body allocation pass in release.

Retained integration failures: `velocity_submission_failure.log` showed no
movement because the engine node requires an assigned target before submitting
velocity. Assigning a target enables that submission without querying paths.
`async_contract_before.log` expected horizontal movement on the first tick;
the corrected test explicitly waits four physics frames for native avoidance.
Both binaries were built against the pinned prebuilt SDK, without rebuilding it.

The engine's documented [NavigationAgent3D avoidance API](https://docs.godotengine.org/en/stable/classes/class_navigationagent3d.html)
is used; no third-party source or asset was copied into this 0BSD project.

This is local two-actor correctness, not dense-crowd or thermal qualification.
Narrow opposing doorway traffic, queues, many simultaneous goals, stationary
crowds, player avoidance and broader dynamic obstacles remain unqualified.
Avoidance can steer against static collision; the existing stalled-route policy
still applies. Engine avoidance adds runtime work; no GPU/CPU reduction claim.
The world run retained a 173.79 ms startup receive hitch. Water is unchanged.
