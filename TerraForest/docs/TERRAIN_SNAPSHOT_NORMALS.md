# Independent snapshot normal generation

Sparse snapshots can now optionally capture the positive one-sample X/Z border
needed by canonical trilinear field normals. Generation uses owned page data and
procedural parameters after the source World is released. A height cache and
three tagged density planes reuse samples; the normal arithmetic remains the
existing reference implementation, now accepting a sampler without requiring a
World object.

Run `python tools/probe_terrain_snapshot_normals.py`. Ten cases cover 16/32 m
cave and edited terrain, an unaligned region, and both world boundaries. Snapshot
normals match the world-backed cached reference byte for byte, and geometry
remains exact. Two explicit positive-border controls alter stored density outside
the geometry region: positions/indices remain unchanged but reference normals
change. The snapshot reproduces those changed normals after source-world release.

All 30 injected normal allocation failures (height cache, tagged density cache,
output buffer across ten cases) return empty failure results. Ten initial
cancellation controls also return no normals. This does not qualify cancellation
latency during every sampling phase or process-wide OOM recovery.

The extra border can intersect four rather than three pages on each horizontal
axis for an unaligned 32 m owner. The fixed page-index table therefore grows from
153 to 272 entries, adding 476 bytes per snapshot object, including geometry-only
snapshots. Those fixed bytes remain outside the heap allocator budget and are
bounded by the worker's two slots. Normal scratch payload is 9,072 bytes for a
16 m owner and 32,368 bytes for 32 m, in addition to output and captured pages.

The normal pass is not yet connected to the asynchronous worker or Godot packet.
That integration must opt into border capture and expand edit invalidation to
normal sample bounds; the current geometry-only locality certificate is
insufficient. Materials, collision and visuals remain unqualified. Recorded
normal timings are diagnostic only; the final correctness run overlapped extension
compilation and must not be used as an isolated performance comparison.

Both extension variants rebuild, and the existing 17 geometry bridge checks pass.
Evidence: `evidence/terrain_snapshot_normals/terrain_snapshot_normals.json.gz` and
`bridge_after.json.gz` in the same directory.
