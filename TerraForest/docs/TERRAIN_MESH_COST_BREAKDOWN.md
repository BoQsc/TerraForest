# Coarse terrain rebuild cost

The integrated pressure failures are now reproducible in an isolated native
rebuild. `tests/terrain_mesh_pressure.gd` replays all 2,176 commands from the
retained 16× workload and measures patch widths 16–256 m at (1280, 1280), before
and after replay. Three warm-cache repetitions are measured per case. Profiling
is disabled by default, worker-owned and not serialized. Commands 18/19 enable
and read extraction, simplification, legacy-block and shading stage timings.

Mean costs for the 256 m patch, in milliseconds:

| Build / state | Extraction | Simplification | Shading | Whole native call |
|---|---:|---:|---:|---:|
| Debug / fresh | 94.0 | 126.8 | 8.0 | 230.3 |
| Debug / after replay | 107.8 | 104.0 | 49.0 | 266.6 |
| Release / after replay | 96.6 | 94.7 | 44.2 | 240.8 |

Legacy block emission is negligible in this terrain-only fixture. Whole-call
time additionally includes serialization and allocation/release overhead.
Debug 16 m patches remain approximately 1.7 ms before and after replay at this
location. This does not prove all small patches are cheap; it helps distinguish
patch-wide work amplification from a universal per-edit history penalty.

The extraction stage reconstructs a fine surface over the entire patch. Coarse
output is obtained by simplifying that surface afterward. Editing protects
nearby geometry from simplification; more retained vertices can increase
subsequent shading work. Changing only the simplifier cannot remove the measured
extraction and shading costs. Moving the same operation to another thread cannot
remove the response latency already observed with asynchronous execution.

## Required redesign contract

Local density edits must have a bounded dependency footprint independent of the
currently visible coarse patch. Unaffected reconstructed geometry should be
reusable. Simulation/edit storage granularity and distant rendering aggregation
must be separate decisions. Distant updates may be scheduled asynchronously,
but local geometry and collision must remain coherent and uncovered holes or
permanently stale terrain are unacceptable.

Before accepting a replacement, measure cold and warm cost, scratch/cache memory,
changed geometry volume, upload cost, and retirement cost. Verify edits across
all tile boundaries, overhangs, caves, material transitions, changes of LOD,
travel/reload and cancellation. A smaller mesh chunk alone is not sufficient if
it causes excessive node counts, draw calls, seams or distant detail cost.

## Verification and scope

Both debug and release native profiles preserve complete mesh packet bytes with
profiling enabled versus disabled in all 30 measured cases per build. Malformed
profiling requests are rejected in the release run. Existing native bridge tests
still match the published legacy field/snapshot/mesh fingerprints (31 checks per
current build). Reports and tested source/DLL hashes are retained under
`evidence/terrain_mesh_pressure`.

This is diagnostic evidence, not a performance fix. Native warm-cache timing
excludes scene publication, physics attachment, GPU work and the separate
353/382 ms frame stalls. The integrated foundation remains unqualified.
