# Vehicle changes invalidate local actor routes, 2026-10-15

NativeVehicleFleet emits obstacles_changed(bounds) after accepted spawn, removal
or changed pose publication. The movement envelope merges the old and new
conservative five-metre-radius chassis AABBs (including rotation). Identical
poses and rejected corrections emit nothing. Successful snapshot replacement
emits an empty AABB for full route invalidation. Main-world wiring forwards
bounds to NativeEntityActivation.invalidate_navigation, which only resets
intersecting route data. No route data is serialized.

Single-car world updates now publish their live pose at most every0.2seconds;
fleet mode already synchronizes up to four resident bodies at this cadence.
There is no per-frame stored-population scan. Unchanged parked poses do not
trigger repeated planning. The existing shared12-edge/750us cooperative route
budget and collision readiness remain unchanged. The notification is a route
cache invalidation, not predictive traffic avoidance or a hard latency guarantee.

The main-world fixture installs the real vehicle scene and native actors. After
establishing a route, unchanged pose synchronization preserves its state. Moving
the car and calling the normal vehicle update invalidates the intersecting route,
and the next actor update starts replanning. The prior occupied-exit assertions
also pass. This moves the car as a fixture correction, not a driven traffic test.

Both debug/release DLLs built against the existing prebuilt SDK. The isolated
release vehicle_fleet check passes19 assertions, including spawn bounds, unchanged
pose silence, old/new movement bounds, identity/storage checks and locality with
10000 distant records. Command: python tools/test_native_release.py --godot
<Steam Godot executable> --addon vehicle_runtime --test vehicle_fleet.
The main-world run manifest and console are retained. Temporary world only;
water and save formats unchanged. No new performance or traffic qualification.
