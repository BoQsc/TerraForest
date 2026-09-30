# Bounded density query backend jobs

The existing terrain worker now accepts opt-in `density_ray` jobs with `from`,
`to`, `budget`, `token`, `epoch`, and expected terrain `revision`. Admission checks
types, finite coordinates, world API coordinate limits, nonzero segment length
and budget 1..8192. It copies only these request fields so caller mutation cannot
change an accepted job. Computational traversal remains C++; GDScript only packs,
queues and decodes the fixed-size command/reply.

At most eight density jobs may be accepted without their results being polled.
The count includes queued, executing and completed/unconsumed jobs. A priority
flag cannot move a query ahead of a queued mutation. Queries carry their admitted
native epoch; intervening priority mutations can cancel them. They are not silently
retried with a newer epoch or an enlarged work budget.

Results distinguish hit, miss, work_limit, cancelled, stale and error. A worker
reply whose world revision differs from the requested revision becomes stale and
loses its position/fraction. Token, scene epoch, requested revision and native
build epoch accompany completion. **Consumers must still reject obsolete results
at consumption time**: the world can change after the worker produces a reply.
The terrain stream/player does not yet consume this result kind.

Shutdown reports cancellation for accepted query jobs it does not execute. Results
already completed remain available. Query admission remains closed after stopping.
There is no automatic latest-request replacement or hidden request loss.

## Evidence and remaining work

`python tools/probe_terrain_publication.py --density --godot PATH` passes 38 checks
through the real persistent backend and native world, including the eight-result
cap, ownership snapshot, hit/miss/exhaustion distinctions, revision rejection,
mutation ordering, invalid input and complete shutdown accounting. The existing
`--worker` publication regression still passes all 42 checks.
Reports: [retained evidence](evidence/terrain_density_backend).

This qualifies the tested queue behavior, not end-to-end interaction readiness.
Player hit arbitration, final stale-response rejection, hit normals/materials,
rendered-surface agreement, query latency under meshing load and multiplayer
scheduling remain open. No 1080p graphical or endurance run was performed.
