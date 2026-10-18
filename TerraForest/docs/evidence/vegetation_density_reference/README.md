# Same-world vegetation density reference — 2026-10-18

Fullscreen 1920x1080, readonly southern saved world, stationary camera at
(1024,62,1792), same lighting and frozen foliage wind. Normal/reference/normal
sequence. Screenshot readback excluded from 120-frame measurement windows.

Reference uses the earlier woodland planting recipe: 0.45 m jittered spacing,
24x24 points and a narrow winding clear strip. Added 522 authored plants across
four cells: 448 grass, 39 plants, 6 stones, 6 flowers, 8 low bushes, 15 dry shrubs.
This overlays existing natural cover, rather than replacing it, and thus is a
visual density reference, not an exact production target population.

Inspected normal and reference images: reference materially closes foreground
bare gaps and improves the feeling of continuous ground cover. Its hard patch
edge is a fixture boundary, not an acceptable production transition. Existing
models and full nearby cast shadows retained. No final human acceptance claimed.

GPU median: normal 10.111 ms, reference 11.122 ms, normal repeat 10.194 ms.
Frame p95: 17.482 / 18.158 / 17.264 ms; worst 17.661 / 19.162 / 17.487 ms.
A roughly 1 ms local delta is not evidence for full-world density cost, sustained
60 FPS, old-laptop thermals or movement/streaming performance.

Initial location failed the authored 256-per-cell cap because records already
occupied those cells. Preserve failed run; do not treat partial planting as valid
reference evidence. Test now checks available per-owner capacity before planting.
Offline woodland authoring now restores original native snapshot on capacity,
exclusion-query or surface-timeout failure, and invalidates resident owners in case
intermediate records were published during awaited requests. A native-state test
fills a cell, forces failure after earlier placements, verifies exact rollback,
and then verifies a successful planting remains possible.

Original saved state is restored exactly after comparison; source save is readonly.
Production density is unchanged. Next implementation must extend native procedural
coverage with stable harvest IDs, support/query bounds and mesh LOD costs together;
blanketing authored records is not the runtime solution. Keep stones at their
existing production distribution; the reference recipe's extra stones are not a
request to increase stone density.
