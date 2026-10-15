# Actor/vehicle collision boundary, 2026-10-15

The actor body mask11 omitted vehicle layer4. The before check switches the
existing static obstacle to layer4 and fails: the actor passes through it.
After: body mask15 includes terrain, structures, vehicles and actors; route
support/clearance mask7 includes vehicles but deliberately excludes moving
actors (handled by avoidance/body collision). Both template DLLs rebuilt.

A direct movement check stops at the layer4 barrier, including activation,
sleep/reactivation and collision-readiness invariants. A separate rendered
six-check route fixture detours around the layer4 barrier without crossing it.
This uses a static box with the vehicle layer, not a moving car traffic test.

Single and fleet chassis masks now include actors. Placement and safe-exit
occupancy queries include actors. Wheel support rays retain their previous
masks and do not treat actors as road surfaces. A normal main-world check
installs the actual vehicle scene, obtains a supported exit, places an active
native actor there, and verifies the other side is selected. Occupying both
sides rejects exit. It checks single-chassis and wheel masks too. The first
fixture failed because it assumed a car already existed; the corrected fixture
explicitly installs it through the normal installer. Both logs are retained.

Headless body correctness and graphical route/exit checks are distinct; no new
performance claim. Temporary worlds, no canonical save writes. No water edits.
Collision damage, predictive traffic avoidance, moving-vehicle route invalidation
and combined driving-through-crowds remain open. This fixes layer admission;
it does not claim safe traffic simulation or larger active populations.
