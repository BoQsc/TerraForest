# Saved northern tower traversal — 2026-10-18

`tests/northern_tower_walk.gd` loads northern_district_42_20261018 read-only
at 1920×1080 fullscreen with active/background limits of 60 FPS. It confirms
12 northern door instances and selects the entrance nearest the regional center.
After staging at that entrance and waiting for local terrain picking and building
collision, the production player walks to the closed door, opens it using E, then
walks a continuous 18-waypoint route through both stair flights to the third floor,
down again, and outside. All waypoint arrivals require horizontal distance <0.15 m,
height error <0.2 m and grounded state. No jumping, flight, terrain modifications or
repositioning occurs after staging. Player physics is explicitly stepped once per
physics frame through the normal game controller; this is correctness evidence,
not a frame-time or thermal benchmark.

PASS in 35.60 seconds including loading. The exit screenshot was inspected.
The first attempt queried terrain immediately after the general loading flag
cleared and got no hit; the final test waits up to eight seconds for the specific
approach ray, matching existing entrance checks. No production change was needed.

Scope: one saved seed-42 tower, its entrance and two flights. Other entrances,
rotations, interior contents interactions, neighborhood landscaping and sustained
performance remain unqualified by this check. Save data is never modified.
