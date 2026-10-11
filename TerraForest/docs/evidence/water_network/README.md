# Conserved finite settling across independent terrain regions

2026-10-11. NativeWaterNetwork joins region-local storage through the live reciprocal
boundary registry, compiles a compressed basin forest and owns its finite equilibrium
state. Water no longer stops at a compilation-region boundary in these native checks.
Original implementation is 0BSD; no dependencies added.

67 debug and clean-release checks pass. Two independently sampled regions contain a
ridge whose boundary opening is 4 m. A 1,248,000,000 ml pour reaches the correct 5 m
level on both sides. Withdrawal below the sill lowers the targeted side while the
opposite basin retains water at 4 m. Every solver event preserves total-plus-pending
input, or retained-plus-removed output. Reversing region input and using one-operation
compilation yields the same equilibrium. Disconnected caves remain separate roots:
overdraw from one cannot take water from the other. Finished compile/settling calls
do zero further work.

A separate actual native-terrain integration excavates a cavity at (800,24,1304),
straddling two region owners. Each density field is sampled independently through
TerrainCore. Both geometry owners publish and compile with 26 common anchors.
The two local minima collapse to one physical body. Pouring 129,857,198 ml reaches
24 m on both sides; removing 1,000 ml from the other region leaves 129,856,198 ml.
The native network takes 1,004 compilation operations in eight budget-128 calls;
largest measured call 484 us. This is an in-memory terrain edit and finite-state
integration, not a rendered or saved-world fluid test.

## Targeted routing failure found and fixed

The first nested-ridge test conserved quantity but put incoming water in a farther
basin across a dry internal ridge. The old compiler assigned newly exposed air to a
merged component's generic representative. That preserves connectivity but loses
the physical receiving catchment. routing_failure.log/json retain the failure.

New air cells now inherit labels from lower neighbours, then propagate deterministic
nearest-seed drainage labels across equal-height air. Actual cross-catchment graph
faces witness each merge's entry leaf. This replaces arbitrary representative entries.
Both a two-minimum receiving region and a three-minimum cascading region now fill
the basin next to the opening, then the next basin, while the farther basin remains
dry. The 58-check basin suite still passes in debug/release, including 20,592 seeded
flood comparisons and reversed edge order. The 73-check settling suite passes in
both builds; 44 profile and 36 join regressions also pass. This is deterministic
graph-based equilibrium routing, not fluid momentum or a velocity/pressure field.

## Ownership, admission and accounting

NativeWaterProfiles.begin_region explicitly compiles open or disconnected regional
storage; the original begin retains its closed-component gate. NativeWaterSettling
adds configure_forest and aggregate quantity accounting while preserving separate
root capacities and withdrawal targets. The original configure still requires one
connected tree.

A network admits only ready registry owners whose exact immutable graph objects
match its profiles. Every outgoing port must resolve to compatible geometry in the
selected set. Omitted or unresolved neighbours reject compilation; they are never
silently turned into a sealed wall. All profiles use the same height anchors, and
new cross-region merge heights must be exact anchors too. Missing sill anchors fail
instead of silently interpolating a storage threshold.

Generation changes cancel unfinished compilation. After publication they freeze
new actions, solver continuation and level queries on stale geometry. Existing
quantities remain available in statistics. A partially settled pour retains both
its credited amount and pending remainder. This is a hold state for later remapping,
not automatic recovery; gameplay item debit/credit and save transactions are not
implemented. Generation checks are scoped to the retained registry instance.

## Bounds and costs

At most 64 regions, 4,096 local storage leaves, 98,304 compressed input edges and
256 common anchors are admitted; solver hierarchy depth remains limited to 64.
Compilation uses 1..2,048 operations per call with a soft elapsed-time check every
32 operations. Boundary admission and compressed-graph construction are incremental.
Final solver configuration remains synchronous and worker-owned; its maximum-size
cost is not a game-frame guarantee. Current-owner checks inspect at most 64 owners
per public operation. A production scheduler still needs locality and mixed-workload
qualification.

The basin compiler now releases its heap, adjacency, disjoint-set and drainage
scratch after successful publication. Profile compilation releases floating-point
accumulation scratch. The ridge basin report retains 205,828 logical array bytes,
down from the previous compiler's 829,056-byte retained payload. New drainage
compilation needs extra temporary adjacency/queue storage (bounded by twice the
edge count and node count), so lower retained memory is not lower peak build memory.
Network publication releases its temporary compressed hierarchy and merged rows.
Input geometry/profiles remain retained while the network is alive.

Worst-case profile table payload during assembly is roughly 32 MiB (input rows,
merged rows and solver tables), plus geometry, compiler storage and allocator/object
overhead. Latest network calls peak at 452 us debug and 450 us release for these
fixtures. These observations do not establish sustained 60 FPS, thermal safety,
large-lake scalability or multiplayer readiness.

## Remaining full requirement

Preserve and redistribute quantities when mining/placing terrain changes topology;
resolve pending work across edits; control profile interpolation error; preserve
boundary summaries for unloaded regions and avoid requiring an entire unbounded
water body loaded at once. Then integrate the worker scheduler, changing water
meshes/immersion, bucket items and atomic world/item saves. Transient visible flow,
large-world pressure cases and long-run qualification remain open. Playable lakes
still use their static runtime path.
