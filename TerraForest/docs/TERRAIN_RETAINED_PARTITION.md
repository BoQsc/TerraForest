# Retaining surrounding terrain during local replacement

`TerrainCore.experimental_partition_mesh(packet)` splits an existing v5 terrain
packet into four quadtree children in native code. It reads no world state and
performs no density sampling, shading or simplification. Original interior
vertices remain indexed; only boundary intersections add vertices. Position,
normal, material weights and visibility channels are interpolated along original
triangles. A triangle lying entirely on a split plane has one owner.

This supplies retained surrounding geometry for the next local-replacement
integration. The backend accepts a bounded `partition` job, and the stream's
explicit `request_partition(key)` API stages and publishes its four children.
Distance scheduling and mining do not request partitions automatically yet. Connecting a
newly reconstructed edited region to this retained surface remains unfinished;
partitioning an old surface alone does not prove that connection is watertight.
The old mesher's topology and approximation errors are retained, not repaired.

The native packet input is limited to 64 MiB, one million vertices and 1.5 million
indices. Native workspace admission now uses the shared budget allocator before
allocation, including old and new buffers during growth and allocator headers.
The workspace ceiling is 128 MiB; packed output payloads have a separate 128 MiB
ceiling checked before resizing. Caller input, Godot object/allocator overhead,
thread stacks and process memory are outside those budgets. Outputs are
all-or-nothing. Cancellation observes command 12's epoch during geometry work
and output encoding; individual allocations and input decoding are not preempted.

The backend admits only one partition including unconsumed completion. It captures
token/scene epoch/stamp by value and returns them for future publication checks.
Shutdown cancels active partition work and accounts for queued accepted work.
This queue bound does not limit packets already consumed and retained by a caller.

## Validation, 2026-09-30

19 release-extension checks pass: area preservation, recursive partition, linear
visibility interpolation, unique ownership of a coplanar wall, exact matching X/Z
boundary-edge multisets, indexed interior retention, and malformed packet rejection.
Real mountain and cave packets were generated using the current 256 m / step-8
mesher. These checks are headless; they do not prove visual equivalence, collision
behavior, manifold geometry, dynamic edits, allocation-failure recovery or FPS.

| Source | Split ms | Original bytes | Four child bytes |
| --- | ---: | ---: | ---: |
| Mountain (1280,1280) | 2.112 | 268,596 | 309,696 |
| Cave (768,768) | 16.347 | 2,196,876 | 2,269,224 |

These are single-run diagnostic times, not latency bounds or an end-to-end speedup.
Children retain the source LOD step; coarse children do not acquire fine collision
or become valid player-residency evidence merely by becoming smaller owners.

Both native variants build against prebuilt godot-cpp. Reproduce with
`python tools/probe_terrain_partition.py --godot PATH`.
Source fingerprints and the report are in `evidence/retained_partition/`.

## Worker and budget follow-up

43 checks pass after the budget/cancellation implementation, including all prior
geometry checks, tiny workspace/output limits, rejection followed by successful
retry, in-flight cancellation after allocation admission, backend queue bounds,
request identity and shutdown accounting. The separate 42-check snapshot gameplay
publication regression also passes. Both extension variants build successfully.
Current evidence is retained separately in `evidence/retained_partition_worker/`.
The original 19-check report and timings above remain historical evidence.

The cancellation fixture has 1.5 million indices. It verifies actual admitted work
was interrupted, but its diagnostic join time is not a hard cancellation deadline.
The tests do not yet inject every upstream allocation failure or qualify final
scene publication, edited seams, FPS or long-run memory behavior.

## Scene publication follow-up

The stream now stages all four children before installing any of them. Parent
identity, stamp, scene epoch and edit ticket are checked through preparation.
Child reservations prevent ordinary duplicate builds. Cancellation releases
reservations and retires prepared nodes; edits, reload and shutdown abandon the
transaction. Both admission and final publication check resident entry/byte limits.
Source packet encoding still occurs on the caller thread and is not latency-qualified.

Children record their actual inherited LOD step. A 32 m child with step 8 cannot
claim fine player readiness, even if empty. The planner continues to request a
proper replacement for retained geometry coarser than the desired tile resolution.
The parent is retained in cache and coverage changes through the existing planner.

51 headless scene checks pass: three nested partitions (256→128→64→32), held
partial preparation, parent retention, complete child publication, coarse readiness
rejection, fine 32→16 collision replacement with a matching physics ray, parent
stamp invalidation after a child was prepared, cache-limit rejection and shutdown.
The existing 54 transition checks and 42 snapshot-worker publication checks also
pass. These runs do not verify visual seams between retained and newly mined
geometry, automatic scheduling, vegetation, dynamic player motion or 1080p FPS.
Evidence is retained in `evidence/retained_partition_scene/`; reproduce with
`python tools/probe_terrain_partition_stage.py --godot PATH`.
