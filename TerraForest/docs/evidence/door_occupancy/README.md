# Door occupancy interlock

NativeHingedDoors now checks the physics space for collision layers8 (active
actor proxies) and4 (vehicles, including parked proxies) before publishing a
toggle. One BoxShape broadphase query, maximum one hit, occurs per click only.
Player protection remains the explicit capsule-envelope argument. Building
frames are deliberately excluded from this actor/vehicle guard.

Representative StaticBody3D fixtures on both layers reject opening and closing
without changing model pose or hinge snapshot. Removing the obstruction permits
normal use; existing occupied-player, restore and cycle checks pass. before.log
retains the pre-fix failure (subsequent failures cascade after unintended opening).
The real actor route through a generated cottage still passes entry and return.

Both debug/release binaries were rebuilt with Zig and prebuilt godot-cpp;
runtime evidence uses debug. No per-frame work or full entity-store scan is
introduced. Physics broadphase cost at large density, sleeping actor policies,
static obstruction checks and automatic NPC door use remain unqualified.
