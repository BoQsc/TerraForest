# Candidate output limits and cooperative cancellation

The isolated native mesher now returns an explicit status: success, output limit,
or cancellation. Vertex and index limits default to 1,000,000 and 3,000,000;
these are provisional prototype ceilings, not an accepted per-region budget.
Callers can supply tighter limits.

Before inserting a new vertex or triangle, the mesher checks the corresponding
limit. Vector growth requests are clamped to that limit. On failure it releases
the partial position/index buffers and crossing map and returns empty geometry
with the failure status. A resource-limited result must never be interpreted as
a successfully empty terrain region.

An optional callback is checked before each density layer, before each cell row
and after each layer. Cancellation therefore stops between those units, not
inside an individual density-plane fill, tetrahedron operation or allocation.
No wall-clock cancellation deadline has been established. The sequential sampler
is constructed before meshing, so initial height/two-plane setup is not covered
by these callback checks. Runtime integration must account for that work.

## Adversarial controls

The 256-alternating-layer fixture exercises:

- Four vertex limits: zero, one, ten and one below the complete output size.
- Four index limits: zero, two, thirty and one below the complete output size.
- Cancellation on callback calls 1, 5 and 1,000. The latter two must first
  accumulate nonempty geometry, then discard it fully.
- A subsequent build with exactly the required vertex/index limits. It succeeds
  and matches the unrestricted geometry byte-for-byte; observed vector capacities
  on the pinned toolchain do not exceed those limits.

All twelve controls pass. All fifteen real-field fixture hashes and prior
topology, sampling and partition checks remain unchanged. The complete probe
passes **25 checks**. This is deterministic injected cancellation, not a
concurrent epoch-race test. No runtime worker or publication integration is added.

The current standard-library containers still have no recoverable allocation
failure path in this exceptions-disabled diagnostic. Output element limits are
not a complete process memory guarantee: allocator overhead, hash buckets,
reference buffers and output held by controls remain separate. Input dimensions
and providers remain trusted internal fixtures. These limitations prevent
advertising this as a resilient production mesher yet.

Run `python tools/probe_terrain_tetra.py`; evidence and hashes are retained in
`docs/evidence/terrain_tetra_build_limits/`.

## Native epoch across threads

A follow-up connects the callback to `terrain_build_epoch` and advances the
epoch with `terrain_cancel_builds`, using separate `BuildControl` objects for
two worlds. A real `std::thread` runs the mesher on the alternating-layer field.
A condition-variable barrier holds its fifth cancellation checkpoint after it
has accumulated **119 vertices**. The controlling thread advances only that
world's epoch, builds an unaffected second-world result, releases the barrier
and joins the worker.

The interrupted result has cancellation status and empty geometry. The other
world's epoch and mesh remain unchanged. A retry using the advanced epoch
reproduces the complete reference bytes. Startup synchronization has a five-second
timeout and joins/releases the worker on the timeout path; no sleep-based race
is used. The full probe now passes **26 checks**.

This establishes cross-thread epoch observation and isolation for the candidate
callback. The two world objects supply cancellation controls only; the geometry
input is the retained immutable synthetic field. It does not test concurrent
world mutation or connect the candidate to the Godot worker, packet codec or
publication state machine. The deliberately held checkpoint is not cancellation
latency evidence. Initial sampler setup and allocation-failure limitations above
still apply. Evidence is retained separately in
`docs/evidence/terrain_tetra_epoch/`.
