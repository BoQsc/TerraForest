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

A new shallow-source regression currently fails: a positive-air seed in a2cm-deep
puddle is rejected by the old all-eight-corners-air admission policy. Finite pours
must work in partial cells; remove that dependency with solid/open-edge/cache tests
before assuming the existing builder can represent bucket-scale water.

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
   a second update budget to detect scheduling-dependent volume errors. Not done.
3. **Sleeping/scaling:** many settled bodies plus a local change; measure zero solver
   work for sleeping bodies, localized wake-up and fair progress under pressure.
   Preserve failures. Do not infer performance from the accounting tests. Not done.
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
