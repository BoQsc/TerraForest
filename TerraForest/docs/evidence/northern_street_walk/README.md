# Northern street loop — 2026-10-18

The saved northern_district_42_20261018 world was loaded read-only at 1920×1080,
fixed 60 FPS. The test locates the two streets from saved road anchors, stages the
player once on the northern arterial, then supplies ordinary W/Shift movement and
camera direction. No further relocation, jumping, flight, terrain edits or collision
bypass occurs. Both streets and both cross-connections are traversed before returning
via the original arterial connection.

All eight waypoints passed, each within one horizontal metre, grounded and outside
loading mode. The saved district grade is 58 m and the arterial target is 55 m;
the normal graded connection was traversed in both directions. The whole check
took 54.26 seconds including startup and arrival. Movement-frame p95 was 16.883 ms,
maximum 17.866 ms. No image capture interrupts these timings.

This verifies this street loop on the saved seed-42 district, not every seed,
building interior, doorway, vehicle cornering case or long-run thermal workload.
Loading state is retained at waypoints rather than asserted on every frame.
The visually abrupt terrain shoulders in the aerial review remain an art/landscape
issue; the tested street centre routes are passable.
