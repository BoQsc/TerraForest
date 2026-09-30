# Bounded native snapshot worker prototype

`experimental/snapshot_worker.hpp` connects sparse capture, independent geometry
meshing and allocator admission. It owns one native thread and two fixed slots.
Slots remain occupied through queued, running and completed-unconsumed states.
Accepted work is selected by submission serial. Snapshot and mesh heap allocations
use separate caller-sized budgets; mesh scratch and output share the mesh budget.

Capture runs synchronously during submission. The caller must serialize it
against source-world mutation. The worker never accesses the source World.
Completion consumption compares both epoch and revision, discards stale geometry,
calls a consumer with an ephemeral const result and releases the slot. The caller
must serialize this final validation/publication against authoritative changes.
The callback must not reenter the worker or retain references to its buffers.

Stop closes admission, requests cooperative mesh cancellation and joins the
thread. Every accepted slot remains consumable with either its completed result
or cancellation/failure. Destruction joins before freeing slots, and frees slots
before the allocator owners. Call stop from the owner, not concurrently from
multiple threads or from the consumer callback.

Run `python tools/probe_terrain_snapshot_worker.py`. Seven groups pass:

- Two outstanding slots reject a third request, including unconsumed results.
- Two successful completions preserve exact geometry and drain tracked bytes.
- A real edit after admission rejects old-revision completions.
- An epoch change rejects completions with otherwise matching revisions.
- Stop accounts for both accepted jobs, rejects new work and permits draining.
- A zero mesh budget produces explicit empty allocation failures.
- A zero snapshot budget rejects before job admission.

These are native prototype tests. The edit test does not force a particular
instruction-level overlap with meshing; it changes authority before consumption.
The epoch test is not an actual Godot world reload. Capture lock latency, worker
startup failure, callback duration and continuous workload fairness are not
qualified. Stale running jobs are discarded at consumption, not proactively
interrupted by edits. No material, normal, collision or render packet is emitted.

The prototype remains outside the registered extension and gameplay backend.
Runtime mining latency and 1920x1080 performance remain unresolved. Retained
evidence: `evidence/terrain_snapshot_worker/terrain_snapshot_worker.json.gz`.
