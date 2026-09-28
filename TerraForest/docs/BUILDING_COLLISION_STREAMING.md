# Incremental block collision admission

Follow-up: walking now uses local native readiness bounds as documented in
BUILDING_MOVEMENT_READINESS.md. Statements below about the absence of a movement
gate describe the original collision-streaming milestone; vehicle and static
model readiness remain unfinished.

The previous whole-chunk path could create a 491,520-triangle sphere collider in
one call, taking roughly 1.3 seconds in the retained baseline. The block runtime
now creates one piece of at most 1,024 triangles per collision tick. It extracts
only that piece from retained native-produced vertex/index arrays; it does not
read back or expand the entire render mesh each tick. The nearest incomplete
visual chunk is selected first.

Each chunk owns one static body. Its layer and mask remain zero while pieces are
being added. After the last piece is installed, the body activates on layer two.
Physics shape vertices and winding match the render triangles; no simplified
sphere, stair or slope proxies are introduced. The shape/node count increases,
but no node is allocated per authored block.

Leaving collision range, visual eviction or replacement disables the old body
and places it on a retirement queue. Up to four shape or empty-body destructions
run per tick. New admission waits until that queue is empty, preventing repeated
edits/travel from accumulating both retiring and replacement shape populations.
Retired bodies remain children owned by the world until reclaimed. Destruction
of the entire world still synchronously frees its remaining children.

The packed source arrays remain with each resident visual for future admissions.
`source_payload_bytes` reports their logical vertex/index payload. This is extra
retained CPU data, not a complete engine allocation measurement, and is separate
from the existing uploaded mesh budget and retained bake-cache budget. Shapes,
physics acceleration structures, nodes and server memory are not covered by
that payload figure. Shape admission is bounded per tick, not by a new global
physics-memory budget.

## Readiness and API semantics

`collision_stats()` reports `ready`, `pending_chunks`, `ready_chunks`,
`unresolved_mesh_chunks`, live/retired pieces and bodies, source payload, work
limits/counters, and tick/cooking/attachment/activation/retirement timing maxima.
Retirement timing includes the initial residency scan and body deactivation.
`ready` is false if collision is disabled, any near visual is incomplete, or
near authored chunks have dirty, outstanding or deferred mesh work. A settled
chunk with no surface triangles requires no body. Readiness covers the current
local focus/radius, not a future travel path or an arbitrary region.

`stats().collision_chunks` counts completed bodies. `is_idle()` retains its
mesh-bake meaning and does not imply collision readiness. `flush_bakes()` is an
explicit blocking offline operation and now drains collision admission and
retirement fully. It must not be used in a gameplay frame loop. The main world
shows a pending-collision notice; player/vehicle movement is not yet gated by
this readiness signal.

## Limits

One piece is a work bound, not a hard time bound. Engine cooking, attaching a
shape and activating the completed body remain non-preemptible. Broadphase and
physics simulation costs occur outside the measured native collision tick.
Very dense chunks take many frames to become traversable (480 ticks for the
baseline sphere chunk). No collision bake cache, per-region physics memory cap,
predictive vehicle corridor, or multi-hour dense-settlement guarantee is added.
Old collision remains available until a replacement mesh publishes, then is
disabled while replacement collision is built. Applications must account for
that readiness gap.

The original baseline is retained in BUILDING_COLLISION_PROFILE.md. Current
verification results are retained in `evidence/building_collision_stream/`.

## Measured verification

Godot 4.7.2 Steam, Windows debug and clean release: 13 checks each pass on a
4,096-sphere chunk (491,520 triangles). Admission takes 480 ticks, each admitting
one piece. Tests verify inactive partial bodies, exact final physics rays at
nine sites, bounded retirement, travel away during admission, editing while
partial, unchanged authoring during residency cycles, and mesh-budget rejection
remaining unready with no retired bodies left.

| Native collision tick | Debug median / maximum ms | Release median / maximum ms |
| --- | ---: | ---: |
| Admission, 480 samples | 1.195 / 2.593 | 1.277 / 9.330 |
| Retirement, 121 samples | 0.275 / 0.857 | 0.266 / 1.613 |

Across the complete tests (including offline edit replacement), debug/release
maximum cooking times were 1.777 / 3.916 ms, attachment 1.711 / 8.646 ms,
activation 0.119 / 0.322 ms, and retirement/residency scans 0.857 / 2.241 ms.
An earlier pre-instrumentation debug run had a 26.215 ms total tick; its exact
cause was not isolated. The final timings do not establish that larger spikes
cannot recur. These measurements exclude physics simulation and presentation.
The old baseline measured a whole admission in one call; comparison demonstrates
work distribution, not an equivalent end-to-end latency benchmark.

Existing native structure checks pass 281 checks in each binary variant,
including shape physics, stale output, authoring, history and streaming.
The integrated world passes all 148 checks at 1920x1080 fullscreen, including
player support on buildings, stair flights, doorway traversal, prefab editing,
vegetation exclusion, persistence and travel away/back. That run is a modest
construction scene, not the dense-sphere workload rendered at gameplay speed.
