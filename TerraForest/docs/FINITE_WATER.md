# Finite volumetric water: required gameplay foundation

User requirement, 2026-10-11: real manipulable volumetric water, efficient enough
for the same playable world as volumetric terrain. Static fixed-level lakes alone
are insufficient. This supersedes the earlier decision to move past water with a
static-basin limit. Completion remains unproven until the gates below pass.

## Required behavior

Water occupies connected three-dimensional free space, including caves, rather
than only an outdoor height field. Every basin, active flow region and carried
container owns a finite quantity. Scoop/pour moves that quantity; it never merely
changes a visual plane or spawns an inexhaustible lake. A bucket can retain a
partial fill, move between inventory/toolbelt/storage and be dropped and recovered
without losing or duplicating contents. Empty hands and other tools keep their
existing interactions; bucket actions join the unified interaction path.

Excavation can connect, split or drain bodies of water. Adding terrain displaces
water; it must not silently delete it. Gravity and communicating passages determine
redistribution. Disconnected cavities stay dry until a passage admits water.
Explicit world generation/editor sources are separate from gameplay transfers.
Any intentional source/sink must be represented and auditable.

Authoritative water quantity and ownership survive save/reopen, region retirement
and reload. Meshes, lookup indexes and settled geometry are derived caches.
Loading an old static lake requires an explicit one-time conversion from its
occupied volume, not reinitializing its quantity each time it is loaded.

## Architecture constraints

- Native C++ owns quantities, terrain capacity/connectivity and flow scheduling.
  Scripts provide UI, item wiring and mod support.
- Sleeping settled water does no simulation work. Use cached settled geometry;
  wake affected regions when transfers, terrain edits or neighboring flow change
  their state. Rendering and immersion queries must share the same published state.
- Active flow needs a sparse three-dimensional representation with finite capacity
  and terrain face openings. It must handle overhangs and stacked caves. The exact
  spatial solver is still to be selected/proven; a quantity ledger is not that solver.
- Every update has explicit work/memory limits and retained unfinished work. No
  whole-lake scan or unbounded flood should run in the player interaction handler.
  Back-pressure must retain water and continue later, not drop it or fake completion.
- Ownership transfers across regions and containers commit atomically. Unavailable
  regions defer/reject safely. Commands carry revisions for authority/replay handling;
  clients do not independently create authoritative quantities. Networking remains
  future work and is not proven by local revision checks.
- Current lake terrain sampling, connectivity tests and shoreline extraction can be
  reused where compatible. Their fixed fill height cannot be the authoritative amount.
  Do not replace established terrain, vegetation or movement systems for this work.

## Implemented first contract

`NativeWaterQuantity` is an optional standalone quantity owner in the water addon.
Amounts are signed API integers constrained to nonnegative millilitres internally;
1 cubic metre is 1,000,000 ml. Transactions never use floating-point subtraction.
`create(capacity_ml, initial_ml, expected_revision)` is an explicit initialization
source, not a normal scoop action. `transfer` moves an exact requested quantity or
rejects the entire operation. `remove_empty` refuses to delete water. IDs are never
reused. Queries and transfers use a bounded ordered map; no tick or per-frame scan
exists. The current cap is 4096 records per store, not a whole-world capacity claim.

Version1 quantity snapshots have a bounded 98,352-byte maximum, sorted records,
checksum, total, identity cursor and revision. Decode stages before publication,
checks balances/capacities/identities/aggregate limits and only admits into a fresh
store. The checksum detects corruption, not malicious forgery. Store commands must
be serialized by their owner; revisions do not make it thread-safe. This is not yet
wired into world snapshots or inventory item metadata.

## Geometric quantity measurement

`NativeWaterCapacity` now measures connected positive-density tetrahedra below the
fill surface in resumable native cell-budget steps. It shares geometry with the
lake renderer and queries; full cells have a cheap path. Round once to millilitres
when initializing authoritative quantities, not on every future flow update.
49 debug/release checks pass; see [capacity evidence](evidence/water_capacity/README.md).
This supplies geometric measurement only, not a spatial redistribution solver.

The shallow-source gate now passes: a2cm-deep,533ml puddle with zero wholly empty
cells is admitted, measured and restored from cache. Solid seeds and open boundary
connections still reject. The obsolete full-cell flood/queue was removed; connected
tetrahedra now determine admission and full-cell occupancy is only a fast path.
See [shallow-source evidence](evidence/water_shallow_source/README.md). This proves
small-source geometry, not quantity-driven level changes or playable pouring.

## Native settling component

`NativeWaterSettling` now consumes supplied cumulative storage curves and a basin
hierarchy. Fill/spill/merge and withdrawal/split run through a persistent bounded
work stack; settled state requires no solver tick.73 debug/release checks pass,
including nested/dry-sill cases,2000 unequal-area oracle commands, budget independence
and4096 leaves. See [settling evidence](evidence/water_settling/README.md).

This is hydrostatic equilibrium on supplied topology, not yet terrain-driven flow.
The next required implementation is bounded3D terrain hierarchy/profile extraction,
including correct spill contacts, stacked caves and an explicit approximation bound.
Do not assume a2D height-field depression hierarchy alone handles overhangs. Tree
configuration is still synchronous. Geometry remapping, mass displacement, save
ownership and atomic bucket/world publication remain open. No full velocity/pressure
field or transient water presentation is provided by this component.

## Terrain connectivity compiler: regional intermediate

`NativeWaterTopology` now extracts regional tetrahedral connectivity and opening
heights from sampled3D terrain.42 debug/release checks cover ridges, stacked caves,
regional boundary stitching, budget independence and cache restoration. A separate
actual native-terrain excavation integration passes. See
[topology evidence](evidence/water_topology/README.md).

The graph now feeds `NativeWaterBasins`, a resumable plateau-aware merge-forest
compiler. 58 debug/release checks and actual native-terrain integration pass; see
[basin evidence](evidence/water_basins/README.md). Flat terrain compacts to one
basin; a ridge yields two basins with the measured sill. External ports survive,
and incomplete/deep forests cannot silently enter the closed settling solver.
`NativeWaterProfiles` now compiles actual terrain storage curves into settling.
44 debug/release checks pass, including finite cross-sill pour and withdrawal with
conservation at each event, plus actual native-terrain crater integration. See
[profile evidence](evidence/water_profiles/README.md). Coarse one-metre anchors
show unacceptable interpolation error; two-centimetre anchors improve the measured
fixture, but adaptive/error-controlled selection remains open for tall domains.
Same-snapshot regional compilation now joins through a bounded native path:
36 debug/release checks reproduce whole-domain geometry, basins, profiles and finite
settling. See [join evidence](evidence/water_join/README.md). This is not exchange
between independent world regions. NativeWaterField now admits raw open terrain,
including a native sampler with revision/epoch and terrain-owner checks. 36 debug/
release checks and 11 actual-terrain checks pass; see [raw-field evidence](evidence/water_field/README.md).
World-addressed reciprocal ports and disconnected caves survive compilation.
NativeWaterRegions now gates reciprocal boundary readiness with generation tickets,
exact face samples and bounded publish/retire work. 38 debug/release checks cover
cancellation, stale completion, unloading, vertical boundaries and endpoint pressure;
see [region evidence](evidence/water_regions/README.md). It does not transfer liquid.
NativeWaterNetwork now couples open-region profiles through validated boundaries
and performs conserved finite settling over a closed active set. 67 debug/release
checks and actual two-region terrain excavation pass; see [network evidence](evidence/water_network/README.md).
A nested-ridge check exposed and fixed wrong receiving-catchment routing. Disconnected
roots remain separate, and stale geometry freezes quantities instead of discarding them.
Next implement quantity-preserving edit remapping and unloaded-boundary summaries,
then world/item/save integration. Local graph IDs remain
snapshot-scoped; world IDs and coordinates do not by themselves authorize exchange. Keep intermediate memory and
concurrency bounded; do not retain one simulated body per tetrahedron.

## Gates and remaining work, in order

1. **Quantity contract:** exact scoop/pour, partial fill, over-capacity rejection,
   replay rejection, identity lifetime, overflow and corrupt/save round-trip tests.
   Implemented; debug and clean-release checks pass. See evidence below.
2. **Spatial conservation:** isolated two-basin/dam/cave fixture with real terrain
   capacity and bounded native updates. Assert total quantity at every step, correct
   final levels, no solid penetration, drain/split/merge and displaced water. Include
   shallow partial-cell puddles, a submerged connection between unequal basins, a
   high dry sill that must not teleport water, and stacked/disconnected caves. Report
   work counts, peak queue/memory, settling latency and budget exhaustion. Compare
   a second update budget to detect scheduling-dependent volume errors. Shallow-source
   admission passes; supplied-profile settling passes. Terrain-derived regional equilibrium now passes finite pour/withdrawal checks.
   Finite equilibrium across a fully ready closed set of independent regions now passes.
   Dynamic terrain-edit displacement/remapping, unloaded-boundary handling and actual
   gameplay remain unimplemented; interpolation accuracy requires explicit control.
3. **Sleeping/scaling:** many settled bodies plus a local change; measure zero solver
   work for sleeping bodies, localized wake-up and fair progress under pressure.
   Preserve failures. Do not infer performance from the accounting tests. Do not instantiate one independently simulated lake per poured bucket; connect
   pours to shared spatial ownership. Not done.
4. **Playable bucket:** actual item/model/icon, toolbelt actions, targeting feedback,
   partial contents, drops/storage and atomic world/item save integration. Test
   scoop, carry, pour, destroy/open barrier, travel away/back and restart. Not done.
5. **World migration and presentation:** preserve existing edited worlds, convert
   static lakes once, water mesh/immersion/vegetation consistency through edits,
   visible flow as needed and no main-thread bulk rebuild. Not done.
6. **Performance acceptance:** fullscreen1920x1080 target60FPS, bounded CPU/GPU work,
   frame tails and repeated edit/flow/travel/save cycles. Keep hardware identity and
   power configuration with results; new-machine timing is not older-laptop proof.
   Long-session stability, thermal sustainability and multiplayer remain unproven.

These gates are a path to the full requirement, not alternative smaller definitions
of completion. Dynamic fluid simulation is not identical to solid terrain meshing;
we must prove its additional conservation and scheduling obligations explicitly.

Evidence: [quantity contract](evidence/water_quantity/README.md).

Spatial query checkpoint (2026-10-11): `NativeWaterNetwork.probe` resolves settled
water against actual tetrahedral void geometry and refuses busy/stale state.
76 debug/release network checks pass; this does not complete terrain-edit remapping.
See [query evidence](evidence/water_probe/README.md).

Geometric remap checkpoint (2026-10-11): `NativeWaterRemapPlan` measures old wet
geometry against edited voids and assigns canonical ml to replacement leaves or
explicit displacement. 141 debug/release network checks, 2,462 analytic clipping
cases and actual repeated TerrainCore excavation pass. The plan does not transfer
ownership: atomic settlement/retirement and displaced-water routing remain open.
See [remap evidence](evidence/water_remap/README.md).
