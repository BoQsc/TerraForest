# Native snapshot contention comparison

Run `python tools/probe_terrain_snapshot_contention.py`.

The probe compares twelve identical 32 m candidate mesh builds while a second
native thread periodically queries the authoritative world. The baseline holds
the same world mutex throughout meshing. The sparse variant holds it only during
capture, then meshes owned inputs outside it. Both modes request a 1 ms sleep
between mesh jobs and between queries. This is a periodic workload, not a fixed
1 kHz load: operating-system scheduling determines the actual sleep duration.

Three fixtures run in each mode three times: cave, edited mountain, and fully
populated local density pages. All 216 mesh outputs match their direct-world
reference byte for byte; every query hits. Each case completes all twelve jobs.

| Fixture | Locked mesh query p95 / max ms | Sparse query p95 / max ms |
|---|---:|---:|
| Cave | 27.70 / 74.15 | 0.014 / 0.054 |
| Edited mountain | 5.86 / 32.25 | 0.039 / 0.085 |
| Fully populated | 31.96 / 36.59 | 0.049 / 1.002 |

Percentiles pool the three repetitions for each mode/fixture. Query latency starts
immediately before mutex acquisition and ends after density traversal. It excludes
the preceding sleep, player-frame polling and display latency. Sample counts
differ because each run continues until its twelve meshes finish.

Median whole-case durations for locked/sparse modes are 421/469 ms, 385/384 ms,
and 583/594 ms respectively. Thus this result supports query responsiveness,
not increased mesh throughput. The longest sparse capture lock hold is 5.89 ms;
not every capture necessarily overlaps a query. The maximum observed query wait
is not a proven upper bound on future waits.

Only one snapshot can be live in this harness. Its largest retained payload and
index table is 1,254,296 bytes, excluding mesh output/scratch and allocator
overhead. This construction prevents snapshot queue growth in the experiment;
it does not implement aggregate memory admission for a production scheduler.

Decision: continue toward a native snapshot job interface, retaining revision
validation and bounded admission. Do not add another caller of the current
long-held World mutex and expect the same result. Test edits/reset/load and stale
completion before runtime use. This harness has no concurrent mutations, Godot
backend queues, normals/materials, renderer, multiplayer or endurance workload.
The existing runtime density latency rejection remains unresolved.

Retained raw query samples and source hashes:
`evidence/terrain_snapshot_contention/terrain_snapshot_contention.json.gz`.
