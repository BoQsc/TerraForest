# Prefab-owned cellar integration

A cottage variant owns its below-ground shell, two-metre opening, taller ladder,
storage and surface-offset/clearance metadata. Site planning grades the surface
first and clears the cellar with three bounded native grading segments before
normal combined block/model placement. Offline GDScript describes the prefab;
native terrain, blocks, collision and player movement perform runtime work.

The shared ladder motor accepts upright vertical scales 0.25-4 with unit horizontal
axes; tilt/shear/horizontal scaling remain rejected. Existing ladder regression
passes. Four rotated cellar plans and opening checks pass. Full regional creation
and fresh-process reload restore exact signatures with 17 buildings, the mine and
11,278 block cells. In that saved world, normal controller W climbs onto the house
floor and S returns through the hatch: final local heights 7.007675 and 1.169731.
The successful test took 42 seconds at fullscreen 1920x1080, cap60 including background.
An earlier 90-second timeout is retained, not counted as passing evidence.

This proves the tested cellar's placement/persistence/traversal, not runtime budgets,
all rotations of physical traversal, large-town coverage or a finished art pass.
Screenshots still show developer overlays. Preparation/loading hitches remain in
logs. Development save: poi_cellar_20261018. Normal launchers are unchanged.
