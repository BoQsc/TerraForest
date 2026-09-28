# Persistent native block worker

Uncached building bakes previously launched a new `std::async` thread for every
chunk. Each block-world instance now lazily starts one native thread on its first
uncached bake. A condition variable puts it to sleep between jobs. There is only
one submission/result slot; a completed result remains outstanding until the
scene thread consumes it. No unbounded background queue is introduced.

The scene thread owns authoring, residency, tickets, counters and publication.
The worker receives a copied 18-cubed halo, key and revision. Shared submission,
result and stop fields are mutex-protected. Baking holds no mutex and touches no
scene nodes or engine resources. Existing ticket checks reject stale output.
Cached returns do not submit worker jobs. Runtime processing polls for a completed
result; only explicit offline `flush_bakes()` waits for completion.

Destruction sets the stop flag, wakes the worker and joins it before members are
destroyed. Pending work can be discarded; an already executing bake finishes
before the join returns. This is safe shutdown, not bounded-time cancellation.
The worker thread and its OS stack stay allocated until its world is destroyed.
There is one worker per used world, not a process-wide worker pool.

`stats()` adds `worker_threads_started`, `worker_jobs_submitted` and
`worker_results_consumed`. `worker_jobs` still counts the single outstanding job,
including ready output, and is zero when idle. These counters are scene-thread
diagnostics, not a supported concurrent authoring API.

## Evidence

Debug and clean release lifecycle tests each pass nine checks: lazy startup,
200 actual edits reusing one thread with 200 consumed results, idle processing,
50 cached return trips without new submissions, two independent worlds, stale
replacement matching a fresh bake, and 40 destruction cycles with outstanding
work. Shutdown tests cover pending or executing work; they do not claim every
cycle observed an executing CPU bake.

The existing structure suite passes 281 checks in each variant. Its stale-output
test now waits for an observed outstanding job rather than assuming a job will
still be pending after two frames. It requires the stale rejection count to
increase for that specific edit. The seven captured mesh fixtures still match
exactly (31 checks), and the 1920x1080 fullscreen integrated construction suite
passes 148 checks. Evidence and binary fingerprints are retained in
`evidence/block_worker/`.

The retained matched headless lattice runs include authoring, worker handoff,
baking and mesh publication; timing changes are not frame-rate guarantees.
The key verified change is eliminating thread creation per chunk while preserving
single-job admission and exact geometry. This short lifecycle test is not a
multi-hour memory or scheduling endurance result.

Region storage, building LOD, city generation, high-speed physics readiness and
long-duration validation remain unfinished. Mesh publication and physics cooking
retain their existing non-preemptible costs. Windows extensions were rebuilt
with Zig and the pinned prebuilt godot-cpp SDK without rebuilding SDK sources.
