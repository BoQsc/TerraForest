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

configure_gravity(acceleration) scales suspension stiffness/force limits from
the authored 9.8 m/s² reference and damping by the square root of that ratio.
The adapter configures this once from project gravity times body gravity_scale.
TerraForest's gravity of 20 otherwise bottoms out the original springs under
the 1650 kg body. Runtime gravity areas and later mass/gravity changes are not
automatically retuned; the current vehicle assumes fixed mass and gravity.

NativeDrivingPolicy also applies the grounded bicycle velocity field, free-mode
driving/braking forces, body stabilization torque and downforce. The adapter
retains the original decisions about grounded/free mode and impact recovery.
The vehicle_demo adapter retains visual effects and interaction scripts
pending migration. Streaming and persistence are supplied by the adapters below;
authority and fleet activation/LOD remain incomplete. The simple CharacterBody controller was discarded
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
Native travel_bounds uses a 3.25 m envelope for this supplied chassis/suspension,
plus travel and acceleration allowance. It is not a generic arbitrary-vehicle
bound, smooth braking system, or guarantee against unbounded external impulses.
Reset discards held momentum. A bound terrain reload signal holds the vehicle
in place and clears speed; it resumes at rest after publication. Reset input
remains usable while held. Multi-vehicle focus management still needs
integration. The ordinary standalone demo remains unbound. The main world also
binds vegetation through `streaming.bind_vegetation(provider)`. Once bound, that
provider remains required; missing or unpublished trunk collision holds motion.

Main world now uses world_vehicle.gd for one vehicle: V places it
on nearby clear loaded ground; E enters within 3.5 m or exits below 1.5 m/s
when either side has clear loaded capsule space. Walking/editing are suspended
while occupied; terrain focus belongs to the vehicle and existing building/
vegetation focus follows its occupant. Parked simulation is disabled. Vehicle
collision uses layer 4, terrain/buildings layers 1/2. Driving uses 120 Hz physics
and restores the previous rate on exit. Door animation and multiple vehicles
are not integrated in this adapter.

NativeVehicleStorage validates a versioned 72-byte position/orientation record
for the supplied vehicle. The vehicles section is registered with compound
world persistence. Missing/empty sections mean no vehicle for older saves.
Restoration produces a parked vehicle at rest, with simulation disabled until
entry. Invalid live poses reject saving rather than producing an empty section.
Cosmetic dents, momentum and occupied-seat state are not persisted. F5 works on
foot and while seated through the compound world pipeline. Seated saves record
a checked on-foot position beside the car; no clear, loaded position means the
save is rejected. Temporary-world rules still apply. Existing vehicles are
reused on restore, resetting pose, held momentum, damage and door state. First
creation remains synchronous and has produced substantial loading hitches.

After setup, the native adapter releases the hidden imported model hierarchy:
35 fewer retained nodes per car. The 32 runtime mesh instances share their mesh
resources across vehicles; cosmetic deformation creates per-instance meshes.
This reduces node overhead, not visible geometry or the number of draw calls.

NativeVehicleCamera now performs the main-world chase follow and a 0.25 m
sphere sweep against terrain, buildings and other vehicle collision (mask 7).
It reuses its shape/query resources and excludes the occupied body. Camera
distance shortens immediately at obstacles and recovers with smoothing. If
the follow anchor is already embedded, update returns false and retains the
previous camera pose; it does not claim to solve that penetration. Only actual
physics colliders participate. Main-world trunks have bounded nearby box proxies;
foliage has no collision. This replaces the main-world scripted follow calculation.

## Validation scope

The tests under `tests/vehicle_*.gd` and `tests/world_vehicle*.gd` cover native
policy parity, suspension, damage, accessories, streaming holds, interaction,
pose storage, seated disk saves, camera sweeps and shared visual resources.
`vehicle_high_speed_collision.gd` tests ballistic chassis impacts at 30–100 m/s
against wall/trunk proxies at 120 Hz with driving forces disabled. It does not
qualify world streaming at those speeds. See `docs/DELIVERY_STATUS.md` for saved
evidence. Sustained populated-world 60 FPS, laptop thermal headroom, fleet LOD,
multiplayer authority and complete high-speed terrain traversal remain unproven.
