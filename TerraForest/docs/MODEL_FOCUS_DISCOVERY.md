# Model destination discovery

2026-10-09. A short targeted check exposed linear destination discovery in the
new model pager before default activation. Native admission selection now uses
a spatial bounds index. The original first-request gate remains unchanged.

## Reproduction and result

| Validated metadata fixture | Previous selection calls to first nearby request | Indexed selection calls |
| --- | ---: | ---: |
| 64 regions in one asset | 1 | 1 |
| 4,096 regions in one asset | 64 | 1 |
| 4,096 regions in each of 32 assets | 2,048 | 1 |

The gate is at most four calls with a shared 64-visit budget and 250 microsecond
soft selection deadline. The original check completed in a few seconds; no long
soak was needed to expose the flaw. Calls are algorithm invocations, not measured
game frames or disk-loading time. At most 131,072 unavailable region records are
represented in the large fixture, with one reserved placement ID per region.

The fixture builds valid native metadata with synthetic checkpoint/region digests.
It deliberately does not tick the transfer scheduler or read nonexistent packets.
This isolates discovery from storage and meshing. Existing scene-adapter tests
separately exercise actual saved packets, admission, edits and reload.

## Implementation

Each native static-model collection maintains an AVL tree of unavailable region
bounds, ordered by interleaved signed coordinates. Each subtree carries its union
box. Insertions and removals update a logarithmic tree path; full metadata restore
builds the index during startup. No new dependency or license is introduced.

Focus selection prunes subtrees outside the requested area and visits nearer
branches first. Continuation stores stable integer keys, not pointers that could
be invalidated by tree rotations. Residency revisions restart queries after
admission/retirement; focus changes over four units restart them with padded query
bounds. Each asset gets a bounded traversal quantum within the shared visit cap.
Cold resident retirement retains its background cursor; it is not the mechanism
for discovering newly needed regions.

Unavailable bounds now include both the visual mesh and collision prototype.
Previously a smaller collision proxy could understate the visual extent. Tests
include a mesh reaching a destination far outside all origin cells while its
collision proxy remains small.

## Evidence and limits

Debug and release pass 50 checks: the three comparison fixtures above, negative
coordinates along Y/Z, high valid X coordinates, a 3D grid across 32 assets,
extended visuals, empty-space rejection, index balance/counts, and shuffled
retirement/admission with exact final records and no stale discovery. All eight
discovery fixtures reach the first request in one call.

Release regressions pass 24 scene-paging, 44 bootstrap/handover, 27 model metadata,
56 incremental retirement and 42 scheduler checks. The scene-paging fixture also
checks index node counts against actual unavailable-region counts during travel.
[Before/after reports, logs and source/DLL hashes](evidence/model_focus_discovery/)
retain the original failure and identify the measured builds.

This closes the reproduced first-request discovery flaw. It does not qualify
whole-destination arrival, every overlapping layout, dense object transfer,
rendering, collision cooking, FPS or thermals. Query cost can still grow with
overlapping bounds and genuinely nearby content. The index adds one native tree
node per unavailable region; this check does not measure total process memory.
Startup index construction and soft-deadline timing tails are not hard frame-time
guarantees. Normal game save/reload/autosave/shutdown barriers remain required
before default activation.
