# Bounded same-snapshot water topology joins

2026-10-11. NativeWaterTopology now accepts begin_join(regions) and advances the
join through advance_join(work_budget). This connects separately compiled pieces
to the existing native basin/profile/settling path without rebuilding their terrain
geometry. It is a bounded compilation operation, not independent world-region fluid
exchange. Original 0BSD implementation, no added dependency.

36 debug and clean-release checks pass. Two-way and four-way partitions reproduce
the full area's exact node IDs, air floors and edge set. Joined output is canonical
under input-order reversal and budget 1 versus 256. Basin ownership, hierarchy,
capacity curves and spill elevations are identical to whole-area compilation.
A finite pour conserves total plus pending quantity every event and reaches the
same 4 m level on both sides of the former region boundary. Unmatched outer ports
survive a partial join; matched interior ports cease to count as external.
The existing 42-check topology suite also passes after the change.

## Ownership and bounds

Every input must be ready, unjoined, disjoint in cell extent, and retain the EXACT
same immutable NativeLakeVolume object. Numerically identical geometry from another
object is rejected; no source-local tetrahedron IDs may cross snapshot ownership.
Overlapping, unfinished, empty, nested, oversized and more-than-eight-piece requests
are rejected before mutation. Limits remain 4,096 total cells, 24,576 nodes and
98,304 input edges. These are not silently raised to aggregate a large world.

The join incrementally merges sorted node streams, heaps edge triples, deduplicates
shared faces and reclassifies ports by endpoint membership. At most eight stream
candidates are inspected per node; heap operations are logarithmic. Conflicting
heights for the same immutable face fail without publishing partial output.
Calls accept 1..2,048 operations and check 2 ms elapsed every 32 operations.
Using the ordinary cell-advance API on a join is rejected; finished work stays idle.

Heap capacity is reserved at admission, at most 1,179,648 bytes, in addition to output
arrays and retained source/input ownership. Scratch allocation and final release
are bounded but not individually time-sliced. The heap's reserved storage remains
until the task is retired; advance_join reports it separately from output buffers.
The two-way fixture uses 134,868 heap bytes and 28,457 operations. Budget-256 calls
peak at 52 us debug and 95 us release. A release budget-1 call reached 2.920 ms:
these are observed headless timings, not hard deadlines or frame/thermal proof.

## Next integration boundary

The source is still a closed, seed-connected potential lake volume. Arbitrary open
terrain regions, distinct-grid world identities, cross-snapshot edit remapping,
authoritative exchange and backpressure across unloaded regions are not provided.
They must not be emulated by indefinitely expanding this bounded join or mixing
source-local IDs. Playable lakes remain static and no bucket/save path changes here.
