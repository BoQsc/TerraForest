# Sparse geometry input capture

The experimental sparse snapshot copies only density pages intersecting a region
plus its seed and cave primitives. Density evaluation and geometry extraction
then use independently owned data after the source World is released. It is not
registered in the runtime extension.

Run `python tools/probe_terrain_sparse_snapshot.py`. All 36 geometry comparisons
pass, including cave, mountain, edited mountain, both world boundaries and an
unaligned region with every intersecting page populated with varying densities.
Each case runs with 0, 32 and 256 additional distant stored pages. Position and
index buffers exactly match the existing candidate's direct-world output.

Capture issues 68 page lookups for these 16 m owners and 153 for 32 m owners,
independent of the number of distant pages. Retained data is also unchanged by
distant pages. This is a bound on lookup count, not on the hash table's individual
probe length or allocator latency.

The ordinary edited fixture retains 33,688 bytes. The fully populated 32 m case
retains 1,254,296 bytes and captures in 0.95–1.13 ms in the retained run. Its later
mesh work still costs 36–44 ms, but no longer needs access to the source world.
Reported bytes include the fixed page index table and buffer payloads, not all
object metadata, allocator overhead, meshing scratch or output. A bounded queue
and aggregate memory budget remain necessary.

This is evidence to continue with sparse capture rather than eager density
evaluation under a world lock. It does not establish actual concurrent query
latency or justify gameplay adoption. Geometry-only capture omits material,
normal halo and lighting dependencies. The implementation explicitly rejects
more than 64 cave primitives; a larger procedural world needs bounded spatial
generation dependencies. Failure injection, cancellation, snapshot handoff and
stale-result concurrency tests must precede integration.

Retained evidence: `evidence/terrain_sparse_snapshot/terrain_sparse_snapshot.json.gz`.
No 1080p rendering, FPS or endurance qualification is implied.
