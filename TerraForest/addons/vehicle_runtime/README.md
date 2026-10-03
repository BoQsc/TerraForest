# Native vehicle runtime

0BSD port of the user's Vehicle Driving Test policy. NativeDrivingPolicy owns
steering command smoothing, speed-dependent authority and cap recovery, and
longitudinal acceleration/braking including the turn-grip budget. One policy
instance belongs to one vehicle. reset() resets steering state after landing,
impact recovery or vehicle reset. steering() returns angle/cap/fraction;
speed() returns speed/acceleration. Inputs use metres, seconds and radians.

Build: `python tools/build_native.py --addon vehicle_runtime --target all`.
Uses the pinned Zig/prebuilt godot-cpp workflow; see its separate MIT notice.

NativeVehicleSuspension samples four wheel rays and applies the original spring
and compression/rebound damping forces in C++. Call sample_and_apply once per
physics tick; it returns four packed rows of contact, load, spring length,
force, world point xyz and normal xyz. Invalid body/ray sets return an empty
array. Automatic ray updates are disabled in the adapter. Effects and telemetry
reuse the sampled contacts. A temporary four-wheel script adapter still copies
the 160-byte result into the original visual state.

NativeDrivingPolicy also applies the grounded bicycle velocity field, free-mode
driving/braking forces, body stabilization torque and downforce. The adapter
retains the original decisions about grounded/free mode and impact recovery.
The vehicle_demo adapter retains visual effects and interaction scripts
pending migration. Neither the policy
nor demo provides streamed collision readiness, vehicle persistence, authority
or fleet activation/LOD. The simple CharacterBody controller was discarded
before integration in favour of preserving the supplied vehicle behavior.

NativeVehicleDamage performs cosmetic dent vertex deformation for static
ArrayMesh assets. It rejects distant impacts using conservative world bounds,
leaves the source mesh untouched and retains materials. Invalid inputs and
impacts affecting no vertices return null. Vertex normals retain the original
demo behavior (not regenerated); this is not a skinned-mesh or blend-shape
damage pipeline. Mesh creation/upload remains synchronous, so this does not
establish a bounded cost for arbitrarily large meshes or simultaneous crashes.

NativeVehicleAccessories owns accessory spring state and cached coefficients.
Configure once with up to 256 mount nodes and matching nonnegative profiles;
step once per physics tick. Node instance IDs allow deleted mounts to be skipped
safely. Disabled motion resets transforms once, then only updates the previous
vehicle velocities. Reset after teleport/vehicle reset. Configuration is
transactional; mismatched arrays return false without replacing existing state.
This moves mount animation calculations to C++; distance-based activation and
rendering LOD remain future work.

The demo car exposes bind_streamed_world(terrain, structures=null). Its optional
streaming adapter updates terrain focus/travel velocity and checks native
collision readiness before and after controls. Missing publication freezes the
body, retains velocity for loading, and restores it when ready. Missing bound
providers fail closed. This adapter assumes sole ownership of streaming focus;
the walking controller must relinquish that ownership during driving.
Native travel_bounds uses a 3 m envelope for this supplied chassis/suspension,
plus travel and acceleration allowance. It is not a generic arbitrary-vehicle
bound, smooth braking system, or guarantee against unbounded external impulses.
Reset discards held momentum. A bound terrain reload signal holds the vehicle
in place and clears speed; it resumes at rest after publication. Reset input
remains usable while held. World entry/exit and multi-vehicle focus management
still need integration. The ordinary standalone demo remains unbound.
