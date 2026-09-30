# Terrain refinement during repeated edits

Two scheduling defects prevented fine terrain from replacing coarse coverage
during repeated mining. Priority edits cancelled the execution epoch of queued
mesh jobs even when their geometry was unaffected. Meanwhile, the same edited
fine children could be invalidated repeatedly before becoming visible.

Queued intersecting meshes are now cancelled explicitly. Unaffected queued work
takes its execution epoch under the submission mutex when it starts, retaining
its original scene epoch and dependency stamp. Later edits can still cancel it.
Retained cached geometry also refreshes visibility, because an edit outside its
geometry can change lighting.

An edit transaction includes up to four requested, affected, invisible 16 m
children. They publish atomically at the same density revision as the current
visible geometry. This bounds the added refinement count and allows repeated
mining to make progress toward fine coverage. It does not bound all possible
meshing costs or remove the first coarse rebuild. Large brushes, unusually
complex fine chunks, and the real held-input/controller path require further
pressure coverage.

## Corrected 2,176-command run

1920×1080 fullscreen, full render scale, Vulkan Forward+ on GTX 1060 Max-Q:

| Measurement | Result |
|---|---:|
| Original control median publication | 20.377 ms |
| Return control median publication | 20.668 ms |
| Return control p95 publication | 51.638 ms |
| Travel publication median | 36.793 ms |
| Travel publication p95 | 450.748 ms — fails 150 ms gate |
| Travel publication maximum | 551.543 ms |
| Frames over 50 ms across measured phases | 0 |
| Largest measured frame | 34.286 ms |
| Initial streaming frame p99 | 27.428 ms — fails 20 ms gate |
| Return frame p99 | 20.189 ms — fails 20 ms gate |

2,164 of the commands changed terrain. The return phase generated 1,532 fine
16 m edit patches, with only 16 patches of 32 m and eight of 64 m during the
transition. The original settled control generated 1,536 patches of 16 m.
The within-run return degradation gate passes; the overall foundation still
fails. Travel worker rebuild p95 is 417.890 ms while worker queue p95 is only
0.489 ms. Coarse meshing remains the primary unresolved latency cost.

This change adds some work to coarse edit transactions. It must not be presented
as a universal speedup: cold travel remains slow, and the corrected run is not
a matched whole-world performance comparison against the older observer-heavy
harness. Dense cities, actual mouse capture/brush queueing, high entity counts,
multiplayer and endurance are not qualified by this test.

## Benchmark observer correction

The original harness synchronously serialized all accumulated edit and patch
events between phases. Independent Godot measurements reproduced hundreds of
milliseconds of serialization cost. The previously reported 353/382 ms boundary
intervals are therefore withdrawn as game-stall evidence. Original artifacts
remain preserved with corrections in their reports.

During capture the harness now serializes only compact progress summaries and
uses shallow copies of immutable event arrays. Complete detailed serialization
runs after frame capture disconnects. Small observer costs remain part of the
recorded intervals; no arbitrary slow frames are filtered out. Engine-memory
figures include retained test events and are not world-only memory measurements.

## Verification

The controlled queue fixture runs against both backend versions. The retained
`717deba` backend fails unaffected-job completion and lighting-refresh checks;
the new backend passes all 14 checks. Original dependency stamps are preserved
and an intersecting queued mesh is cancelled exactly once. The integrated
terrain/forest/building correctness suite covers 167 checks separately.

Full corrected pressure reports, frame CSV, source hashes, observer calibration,
and queue regression results are retained under `evidence/terrain_refinement`.
