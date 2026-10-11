# Routing terrain-displaced water

2026-10-11. NativeWaterRemapPlan now routes displaced volume before integer
apportionment and private settlement. A partly surviving wet tetrahedron routes its
displaced portion to its own surviving storage owner. Completely replaced wet
pieces use a deterministic multi-source breadth-first traversal through the original
wet tetrahedral adjacency. Surviving pieces seed the traversal. Every traversed face
must have a positive old-density aperture strictly below the old water head, and
both endpoints must belong to the same old wet component. This also works across
independently sampled regions through their pinned, previously validated geometry.
New dry or disconnected caves do not become arbitrary recipients.

Each displaced node processes at most four neighbours per work unit; deque-backed
slots, nodes and queues avoid growing contiguous copies during traversal. Slots are
bounded by source topology nodes (at most 64 * 4096 * 6); displaced records and queue
entries cannot exceed that count. This still adds potentially substantial scratch
memory and scans the source active set. Worst-case memory/frame latency, incremental
retirement and dirty-region localization remain unqualified. Completed calls sleep.
The 65,536 sparse overlap cap remains in force and fails without transferring water.

The route is a local geometric displacement rule, not a transient pressure/velocity
simulation. Distance uses tetrahedral hops and stable first-arrival ordering, so ties
and grid orientation can bias which side receives displaced volume. The symmetric
wall fixture distributes 627,425,926 ml and 620,574,074 ml to its two surviving sides;
both receive more than their retained pre-edit overlap. This is conserved and local,
but not evidence of exact continuum symmetry. Do not present it as a full fluid solver.

`displaced_ml` now means unrouteable canonical quantity remaining after routing.
`routed_geometric_ml` reports displaced geometric volume that found a surviving
recipient before normalization to canonical ml. Geometric/profile volume mismatch
remains visible in the existing diagnostics. Routes do not create water.

## Evidence

242 checks pass in debug and clean release. Raised terrain routes its displaced
water to surviving storage and privately settles the full amount. A newly inserted
wall produces two disconnected replacement roots; both sides retain their overlap
and receive displacement. Budget-one results remain deterministic. A completely
filled isolated cave retains its 1,000,000 ml unresolved instead of teleporting it
through rock to the other cave, whose 2,000,000 ml map normally. Full displacement
and capacity overflow still prevent handoff and leave original ownership intact.

The actual TerrainCore check now performs two successive edits and commits, each
resampling and republishing both regions. Enlarging a radius-4 cavity to radius 5
lowers water from approximately 24.000 m to 22.297 m. Placing a radius-2 solid sphere
underwater then routes about 32.619 cubic metres of geometric displacement through
122 completely displaced pieces and raises the water to 22.787 m. Both successful
handoffs preserve exactly 129,856,198 ml. The new solid point is dry. Remap work is
2,207 units for excavation and 4,466 for solid placement in this fixture.

## Limits and next integration

When no surviving wet portion is reachable, water remains unresolved even if some
dry space exists farther away. Dry-space/pressure escape and overloaded-recipient
rerouting are not implemented; commit refuses unresolved quantities. Do not discard
these amounts or silently approve the accompanying terrain edit. A world-level
transaction must coordinate terrain and water publication or retain/reject the edit.
The current test modifies isolated in-memory TerrainCore state; the playable world's
terrain editing has not been connected to this transaction protocol.

Live scheduling, bucket/item transactions, persistence, rendering/immersion,
unloaded boundaries, profile accuracy and 60 FPS/thermal acceptance remain open.
The implementation remains original 0BSD with no new dependency.
