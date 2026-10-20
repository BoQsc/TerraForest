## Generated terrain-cost road corridors — 2026-10-20

Generator15 replaces straight regional road centerlines with bounded offline corridor
searches (25 stations, nine lateral choices per station). Terrain-height and grade
costs choose routes; smoothing reduces abrupt bends, and vertical grades are limited
to12%. Existing settlement transition bands have fixed level approaches. Native
surface/material evaluation and the map share the exact route points through command36.
Height queries reject distant corridors and examine at most five local segments per
road; no runtime pathfinding or per-road scene nodes. Generator IDs1–14 remain intact.

Seven-seed native checks pass: exact route reconstruction after save/reload, fixed
junction endpoints, maximum measured grade0.120001, centerline terrain deviation
0.0711m or less.26 of28 tested roads deviate meaningfully from their straight chords.
The initial check caught settlement blending lifting sloping approaches (up to8.74m);
fixed transition bands corrected it. An exact endpoint rounding discrepancy was also
corrected before publishing. Seven-seed lot-fit checks pass.

Full seed42 district generation and fresh-process reopen passed, publishing the
separate slot `routed_region_42_20261020`. Inspected1920x1080 overview, ground and map
images show a woodland road bend and matching map line. The map capture occurred while
water/block/object overlays were still surveying; it only verifies road depiction.
A continuous on-foot walk through three northern road segments passes with actual
player movement and collision. No teleport occurs between those route waypoints.

World quality remains incomplete: overall topology is still a five-site hub with
four spokes; settlement clusters are regular, shoulders require broader visual review,
and all-route vehicle travel/turning plus sustained performance remain unqualified.
Terrain-cost selection is not an enforcement of the ordinary-site2m fill/3m cut budget
for every road shoulder. These limits must be measured/reviewed before road acceptance.
The next world-design task is the regional location/settlement arrangement; do not
mistake this bend correction for complete natural-world generation. Evidence:
`evidence/routed_region`.

