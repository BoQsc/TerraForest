# Shared snapshot allocation budget

`experimental/snapshot_memory_budget.hpp` supplies a thread-safe allocator for
the existing snapshot's fallible buffers. Atomic admission reserves requested
bytes and the allocator's aligned bookkeeping header before calling its upstream
allocator. Allocation failure rolls the reservation back. Release returns it
only after freeing the underlying allocation. Buffer growth counts old and new
allocations together rather than admitting based on their difference.

Run `python tools/probe_terrain_snapshot_budget.py`. Nine groups pass:

- Zero capacity and size overflow reject before allocation.
- Upstream allocation failure returns reserved capacity.
- Eight simultaneous requests admit exactly two within their shared capacity;
  six are rejected and all reservations return after release.
- Two real snapshots competing for one snapshot's measured heap capacity admit
  one, reject the other without partial valid state, and preserve accounting
  through move assignment.
- Released capacity admits a retry and final destruction returns all bytes.
- Cancellation after capture allocations returns both reservations.
- Replacement-buffer growth cannot exceed the budget while the old buffer lives.

The allocator counts requested heap capacity plus its own header. It does not
measure malloc metadata, fixed snapshot objects/index tables, stacks or mesh
buffers using another allocator. It is not a process-wide RAM limit. There is no
production capacity default: the owner supplies the budget. Memory admission
currently uses the existing allocation_failed status; this does not distinguish
capacity exhaustion from upstream OOM in the capture result.

The budget and any custom upstream context must outlive every allocation. Runtime
integration must enforce this through worker shutdown/join and result draining,
along with a fixed admitted-job count. These lifecycle requirements are not
enforced merely by constructing this allocator. A retrying scheduler must avoid
busy spinning or dropping accepted edits when admission fails.

This component remains experimental. No backend queue, runtime terrain mesh,
Godot rendering or multiplayer performance change is made. Retained evidence:
`evidence/terrain_snapshot_budget/terrain_snapshot_budget.json.gz`.
