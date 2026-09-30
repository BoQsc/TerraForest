# Region snapshot capture experiment

An experimental geometry-only snapshot captures the candidate mesher's density
planes into independently owned storage. It does not change runtime meshing or
the query worker. Run `python tools/probe_terrain_region_snapshot.py`.

The native probe compares snapshot geometry with direct world meshing at cave,
mountain and edited mountain sites, with 16 m and 32 m owners and three repetitions.
It releases the source world before building snapshot geometry. All 18 position
and index comparisons are byte-identical. This establishes independence for the
tested geometry inputs, not concurrent mutation safety or physics correctness.

| Owner width | Retained density bytes | Observed capture time |
|---|---:|---:|
| 16 m | 297,092 | 3.38–4.78 ms |
| 32 m | 1,119,492 | 12.38–18.70 ms |

Capture evaluates all 257 vertical sample planes while the caller must keep the
world immutable. Temporary sampler storage and mesh outputs are additional to
the retained bytes above. No whole-world copy occurs, but a queue of these
snapshots would still require an explicit aggregate memory budget.

**Do not adopt this eager density capture as the scheduling fix.** It moves mesh
extraction outside world ownership, but leaves substantial density evaluation
inside the required protected interval. Its capture cost alone consumes much
or more than a 60 Hz frame interval for the 32 m fixtures. It does not establish
an interactive latency bound under queued captures.

Next, investigate capturing bounded local edited-page data and immutable
generation parameters, then evaluating density outside the authoritative-world
lock. Prove that capture dependencies cover every sample, including boundaries,
and that capture cost does not grow with distant edits. Preserve exact geometry,
revision and cancellation behavior. Evaluate memory and contention before
integrating a second worker.

The snapshot has no material, normal halo, lighting or collision packet. Allocation
failure/cancellation branches are implemented but not fault-injection qualified
here. No runtime concurrency, 1080p performance or endurance claim is supported.
Retained results: `evidence/terrain_region_snapshot/terrain_region_snapshot.json.gz`.
