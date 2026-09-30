# Sparse snapshot lifecycle qualification

`python tools/probe_terrain_snapshot_lifecycle.py` exposed a move-ownership defect:
the implicit move transferred buffers but left the source revision and valid
status intact. The probe checked metadata before attempting source meshing, so
it reported the invalid state without deliberately dereferencing moved buffers.
Three of six check groups failed before correction.

Explicit move construction and assignment now invalidate the source. Assignment
releases the destination's old buffers through their original allocator. Capture
also checks cancellation after the last copied page, and mesh entry checks it
before allocating sampler storage.

All six groups pass after correction:

- Move construction invalidates the source and preserves destination geometry.
- Move assignment replaces existing ownership and invalidates its source.
- Both capture allocation failures leave no tracked allocation live and permit
  a successful retry with exact geometry.
- Each capture cancellation checkpoint in the edited fixture leaves no tracked
  allocation live, no valid revision and no meshable partial snapshot.
- A snapshot transferred into a native thread retains exact geometry after the
  original world is mutated and released before the worker proceeds.

The existing 36 sparse geometry comparisons also pass again. This thread test
uses an explicit handoff barrier; it does not test capture racing a mutation,
concurrent authoritative queries, stale-result publication or lock latency.
The capture caller must still protect the world. Custom allocator contexts must
outlive all buffers that use them.

Retained source-hashed reports are under `evidence/terrain_snapshot_lifecycle/`:
`before.json.gz`, `after.json.gz` and `geometry_after.json.gz`.
Runtime integration, aggregate memory admission, materials/normals and 1080p
performance remain unqualified.
