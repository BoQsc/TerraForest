# Integrated larger lake review — 2026-10-18

Profile 12 retains the POI-owned mine and cellar integration, and adds one roughly
126 m wet-diameter lake with three existing ponds. Static water mechanics unchanged.

- `layout.log`: four-seed basin checks.
- `live_publication_timeout.log`: initial failed cold preparation.
- `offline_publication_timeout.log`: intermediate mesh suppression, still exceeded 180 s.
- `preparation.json`: subsequent full preparation/reopen passed; development slot
  `regional_lake_20261018`, 17 buildings. Offline startup deadline increased to 360 s.
- `cached_view.log`, `cached_view.json`, `water_stats.json`: cached review after
  suppressing unnecessary snapshot capture in temporary/write-disabled worlds.
- `shore.png`: actual 1920x1080 shore capture.

Cached load 18.282 s; arrival 0.899 s; 2,754 cached regions, no water refill,
sampling or region rebuild. Stationary 180-frame p95 16.713 ms, max 16.859 ms.
Resident cell bytes 84,803,384; terrain contact bytes 59,598,776; query cache bytes
57,367,296. These categories are not a whole-process memory measurement.

The preceding corrected-camera run failed after an unnecessary 36.9 s snapshot
capture; its original logs remain in reports/regional_lake_shore_20261018.
The snapshot policy regression passed in reports/checks/20261018T080339434512Z.

## Still open

The original shore image shows ordinary ground cover through shallow water.
The native placement filter now checks the root and 8 cm above it, using bounded
local occupancy rather than a full depth-column scan. Ground cover deliberately
buries its origin 3 cm. The focused buried-root fixture passes; the integrated
image `shore_filtered.png` is clear, with zero submerged roots among 4,221 retained
instances. Both DLL targets rebuilt against the existing prebuilt SDK.

Two subsequent functional checks pass, but stationary p95 degraded to 79.467 and
79.106 ms. This is an unresolved performance failure, not an accepted 60 FPS gate.
Cached loads were 26.537 and 24.871 s; no refill/rebuild. Investigate scene work and
frame pacing before promotion. One GPU sample during the repeat: RTX 4050 Laptop,
48 C, 31% utilization, 8.27 W, graphics clock 960 MHz; insufficient for attribution.

The unchanged legacy water_contact_volume test fails byte-for-byte snapshot
roundtrip and rendered top-triangle assertions. Its failure log is retained, not
reclassified as passing. The dedicated vegetation test is separate.

The circular basin is visually basic.
This is not long-run, travel, thermal, city-scale, or older-laptop qualification.
Default generated-world launchers have not been promoted.

## Frame spike investigation

`update_profile_summary.json` retains four short diagnostic runs. GPU p95 is
roughly 6-9 ms, while slow runs have 75-84 ms wall-frame p95. A diagnostic-only
phase disabling world subtree updates, with the same scene still rendered, reached
17.82 ms p95. This suggests CPU update work; it does not identify the exact source.
Native node callbacks and engine/deferred work are not yet fully attributed.

Per-frame water, ground-cover, forest and optional model-paging timings are now
available. In the slow repeat their maxima were 2.494 ms, 0.104 ms, 0.054 ms and
zero respectively. Another instrumented run reached 16.757 ms p95 without an
optimization. Do not call the intermittent failure fixed or promote based on that
passing run. Next isolate native node updates while retaining these traces.
