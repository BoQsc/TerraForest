# Sustained Godot snapshot transfer test

Run `python tools/probe_terrain_snapshot_load.py --godot <executable>`.

The opt-in release extension builds 32 m owners over a fixed 8x8 grid starting
at (960,960). Cases request 64 or 256 jobs, twice each. The 256-job cases repeat
the same grid four times; they do not increase world extent or edited-page count.
Only two jobs may be outstanding. A separate Godot thread continuously issues
short native density queries with a requested 1 ms sleep between calls. The
headless consumer caps its loop at 60 Hz and discards received geometry after
inspection. This cadence does not measure rendered FPS.

All 640 jobs and 6,569 queries complete without reported correctness failures.
There are no rejected submissions in these runs. Every result token is accounted
for exactly once; all geometry packets are nonempty successful, current results.
The earlier bridge test, not this load loop, checks index ranges and byte parity.

| Jobs / repetition | Total ms | Query max ms | Capture max ms | Poll max ms | Completion max ms |
|---|---:|---:|---:|---:|---:|
| 64 / 0 | 1266.91 | 1.730 | 0.072 | 0.455 | 50.663 |
| 256 / 0 | 4865.20 | 5.123 | 7.362 | 9.811 | 48.932 |
| 64 / 1 | 1264.97 | 0.526 | 6.982 | 0.418 | 48.490 |
| 256 / 1 | 5978.86 | 9.080 | 14.761 | 3.631 | 135.269 |

The provisional gates reject individual query calls over 50 ms or capture/poll
calls over 16.667 ms. Neither fires. Completion measures submission to consumer
receipt, including mesh work and polling cadence; it is retained separately and
has no new pass threshold here. The 135 ms completion and variation between
repetitions must not be hidden by calling this a frame-budget pass.

Transferred geometry totals 252,761,280 bytes across the four cases; the largest
single poll returns 977,880 bytes. These are transfer quantities, not process
memory measurements. The consumer releases successive packets rather than
retaining a growing world, so this test cannot qualify downstream residency.

The test supports further integration of bounded independent meshing and shows
the engine bridge can make progress under concurrent query calls. It is not an
apples-to-apples replacement of the old 256 m worker benchmark: owner sizes,
geometry algorithm and scheduling differ. No edit storm, dense edited pages,
normal/material work, collisions, renderer, vegetation, city or multiplayer
workload is present. The gameplay mining path is still unchanged.

Retained per-call timings and source hashes:
`evidence/terrain_snapshot_load/terrain_snapshot_load.json.gz`.
