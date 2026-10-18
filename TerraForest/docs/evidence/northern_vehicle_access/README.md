# Northern vehicle access — 2026-10-18

Source save: northern_transport_42_20261018, generator 13, seed 42. The normal regional
review launcher now creates/opens regional_world_review_v8. Earlier reviews and
progress remain intact. There is a third vehicle at the north neighborhood's southern
arrival, approximately E1016/S300, facing the arterial from an off-road asphalt bay.
The bay uses the existing terrain edit and saved road-anchor paths; vehicles use the
existing native fleet, collision streaming, shared visuals and native driving policy.
No separate physics or vehicle implementation, and no new native build is required.

The existing street layout first passed a 25-waypoint perimeter/arterial loop with
ordinary keyboard controls. This avoided changing a street primitive that already
supported the intended local turns. The first diagnostic vehicle was spawned for
the fixture; the second integrated test uses the actual saved northern vehicle.

The new bay is planned relative to the northern site. Its new-ground/shoulder footprint
has 99 survey samples; the already paved level arterial strip is omitted from natural
root sampling. Seven seeds pass the project's 2 m fill / 3 m cut limits and geometric
separation from the building footprints. Seed42 observed fill 0 / cut 0.25035 m.
Before grading, the normal world protection check passes; actual collision readiness
and a chassis-space physics query pass before the fleet record is added. The bay
road anchor and all three fleet records survive a separate-process compound reopen.
This survey is specific to new generated sites; it is not an edited-world grading
solver. Previous two parking locations retain their earlier generation path.

The saved-world test performs one initial staging teleport beside the parked car,
then E entry and a continuous drive from the bay through the arterial, all four
perimeter corners and back to the southern arterial. Only keyboard throttle/brake/
steering are applied after entry; no pose, velocity, collision or terrain corrections.
All 28 waypoints pass. Results: max 18.47 km/h; minimum 4 loaded wheels; zero collision
readiness holds; max centre-line deviation 2.792 m. The deviation limit measures the
chassis centre, not a complete swept body-envelope/lane certificate. Middle cross
street traversal, traffic conflicts and high-speed cornering are outside this route.

After handbraking to below 0.15 m/s, M opens the map while seated. Throttle is held
while the map is open: controls remain disabled and the car stays stopped. M closes,
E exits, and capture retains all three identities plus the exact moved car pose.
The drive's changed pose is checked in the captured fleet snapshot, not a new disk
save/reopen of that moved endpoint. Whole-world creation/reopen above proves the
initial generated parked pose. Vehicle state persistence itself has earlier tests.

A separate saved-world visual check confirms the unoccupied activated car is frozen,
not running driving physics and has controls disabled. Bay ground/context and arrival
images were inspected: the bay connects level with the arterial and is clear of the
through-road and nearby cottage. Markings/public-space/landscape design remain open;
this is not overall settlement quality acceptance.

At fullscreen 1920x1080, cap 60, the saved route's timed frames have p95 17.063 ms and
worst 18.481 ms. Whole check 102.12 s includes loading/activation and about 85 s of
bounded local driving. Screenshot readback is after the timed route. These numbers
do not prove sustained 60 FPS, older-laptop thermal headroom, town traffic, larger
worlds or multiplayer. The initial route had p95 17.426 / worst 33.627 ms; different
sampling/workloads mean the difference is not an optimization result.
