# Northern building mix — 2026-10-18

The production recipe replaces twelve tower variants with four enclosed cottages,
two furnished workshops/stores and six two-/three-/four-storey buildings. Pitched
roofs, smaller perimeter footprints, working stores and taller central buildings
provide different massing and uses. Existing native shared prefab/model batches
remain; no new runtime per-building processor. Entrance paths now derive their
start from each building's bounds rather than a fixed tower approach distance.

Seven-seed lot/road fit, road connectivity/separation and native support checks
pass. Seed 42 has 2,536 supported foundation samples; maximum sampled fill is 1 m,
cut 0.261 m. Smaller buildings at the terrain edge reduce cut requirements.
The historical grading-overshoot regression now freezes its original tower fixture
so future recipe changes cannot accidentally remove the case it protects.

Full graphical generation and fresh-process reopen pass without errors in
mixed_neighborhood_42_20261018. Overview and ground-level images were inspected:
different rooflines and massing are present, and the large perimeter cut is gone;
small exposed grading shoulders remain. Existing user saves are unchanged.

All twelve actual saved-world doors pass ground/stair approach, E opening, walking
inside and walking back outside. The test stages at each entrance and runs the
production player physics, not a continuous district route or a frame benchmark.
It does not requalify every upper floor. Existing tower staircase coverage remains
separate. Initial check failed because its one-shot W event was cleared by a second
collision load after staging; the continuous-input helper now maintains the held
movement input each physics tick. No runtime player/stair change was necessary.
The initial diagnostic is retained, not erased by the successful run.

This completes this building-mix integration, not the full world-design standard.
Designed planting/public spaces, sidewalks and vehicle turning remain required.
No sustained performance/thermal claim follows from the captured HUD FPS.
