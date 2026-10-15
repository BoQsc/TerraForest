# Rotated tower rail world persistence

`tests/tower_rail_persistence.gd` extends the two-process browser route observer.
It creates a unique persistent world, places a three-floor tower with quarter-turn
rotation through the production prefab transaction, then uses Actions' save and
return method. A separate graphical process restores the same save.

Both runs use 1920x1080 fullscreen and verify:

- Main-world registration of the new stair-rail asset identity.
- Four sloping rails, complete collision residency and a physics ray through
  each transformed top bar.
- Exact rail identities/transforms and all tower block snapshot bytes after
  reopening, plus the changed inventory covered by the base route.

Passing report: `reports/checks/20261015T213004672487Z`; child logs retained here.
The first fixture had a GDScript Basis-constructor error, fixed to reconstruct
the three basis columns from native row-major storage. That failure is retained.

The elevated fixture intentionally avoids terrain grading and uses free
construction within a paid-gameplay session. It does not prove paid affordability,
human rotated stair traversal, a grounded settlement, dense performance or
endurance. Existing saved user worlds were not changed. The original unrotated
traversal evidence remains in `../tower_stair_rails/`.
