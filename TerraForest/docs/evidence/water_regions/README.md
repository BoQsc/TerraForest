# Active water-region ownership and reciprocal boundary readiness

2026-10-11. NativeWaterRegions provides a serialized, bounded registry for active
raw water geometry. It stores no liquid and performs no quantity transfer. Original
implementation is 0BSD, with no additional dependencies.

38 debug and clean-release checks pass. Region reservations receive distinct
monotonic generation tickets. Invalidating a region immediately disables its old
links. Old tickets, old geometry revisions, foreign worlds and stale unload requests
cannot replace a current owner. Publication and retirement progress under operation
budgets; cancelled partial publication is cleaned before replacement without leaked
endpoints. Unload/reload never reuses the old ticket within the registry instance.

Reciprocal readiness requires both owners fully published at their current tickets,
matching spacing/world, equal compilation ceilings, equal opening heights and exact
agreement on all three face density samples in canonical vertex order. Samples are
compared directly, not by a collision-prone hash. This is conservative: even equivalent
zero surfaces with differently scaled densities fail agreement. Different ceilings,
unloaded neighbours, invalidated neighbours and ready neighbours lacking a reciprocal
opening have distinct blocked outcomes. Readiness is geometric eligibility, not proof
that water is above the sill or that a transfer is valid.

A vertical integration check found that raw fields previously required the ceiling
to fall inside each local field. That would prevent stacked regions sharing a ceiling.
Raw-field ceilings may now lie above or below a field; topology performs clipping.
All 512 faces between vertically stacked regions connect correctly at a shared ceiling
above the lower field. Closed NativeLakeVolume admission is unchanged. Existing raw
field (36) and native-terrain sampler/cancellation (11) regressions pass.

## Bounded admission and lifecycle

One registry owns one world ID and integer spacing. Owned regions are aligned
16-cubed cell blocks. Up to 64 regions (including reservations) and 65,536 endpoint
records are admitted. One publish/retire task progresses at a time; other begin calls
reject while busy instead of building an unbounded queue. Callers must schedule retries.
Existing region revisions and cancellation epochs cannot regress. Generation tickets
are scoped to the registry instance: asynchronous jobs must retain that owner reference,
not reroute an old numeric ticket into a newly created registry. This is not a network
protocol or persisted authority ledger.

New tickets immediately make old records ineligible. A matching publication first
retires old endpoints, then installs new endpoints, then marks the region ready.
Other regions never see partial readiness. Retirement blocks links immediately and
removes entries incrementally. Ready neighbours remain intact. Cancellation retains
the exact inserted-key list so later retirement can remove all partial records.
The registry retains immutable graph references; external references and water quantity
ownership are separate. Runtime unload must eventually preserve canonical quantities
before retiring geometry; this registry alone does not implement that transaction.

The pressure fixture publishes 26 real open-region graphs, reaching 63,232 endpoints.
The next graph would exceed the 65,536 cap and is rejected without state changes.
Retiring one owner frees capacity; the rejected graph then publishes successfully.
A separate 64-reservation check rejects the next active slot. These prove admission
bounds and recovery, not large-world fluid simulation or sustained performance.

Calls accept 1..2,048 endpoint operations; maps provide logarithmic lookup/insertion.
Elapsed time is checked every 32 operations against a soft 2 ms target. Map allocations,
reference release and vector reserve are bounded but not hard real-time operations.
Idle advance performs zero work. Latest largest calls are 797 us debug and 298 us
release; an earlier release run observed 3.610 ms. No frame or thermal qualification.
Memory is bounded by active graph references, endpoint maps and per-region key arrays;
allocator overhead and retained source geometry still need runtime budget accounting.

## Still missing

Open-region storage/solver coupling and conservative exchange; controlled profile
accuracy; edit-driven quantity displacement/remapping; runtime scheduler and rendering;
item/bucket interactions and atomic save/load. No gameplay water behaviour changed.
The registry prevents stale geometric links but does not yet move a millilitre across
independently loaded regions. Playable lakes remain static.
