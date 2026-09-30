# Normal column cache and positive dependency halo

The candidate normal builder now has a bounded column-height cache. It evaluates
terrain height once per horizontal sample column and reads edited pages directly;
it still performs eight density lookups per vertex. There is no persistent cache,
global invalidation, or full-height density allocation. Geometry is unchanged.

The retained [report](evidence/terrain_candidate_normal_cache/terrain_tetra_probe.json.gz)
comes from `python tools/probe_terrain_tetra.py`: 52 checks pass. Five alternating
reference/cached pairs per fixture preserve every normal byte in all 75 pairs.
The scalar World::sample implementation remains the reference for sample lookup.
Both paths intentionally share gradient arithmetic.

In this run, the 32 m cave median falls from 27.0759 to 12.1547 ms. The sum of
fifteen fixture medians falls by 57.2%. These are isolated normal-pass measurements,
not integrated FPS, latency or endurance qualification. Height payload is 4,624
bytes for 32 m and 1,296 bytes for 16 m, plus output normals and allocator overhead.
Density lookup/base evaluation remains substantial; the current implementation
does not reuse the mesher's density planes and is not adopted into gameplay.

The explicit normal invalidation predicate includes the positive one-sample X/Z
halo required by canonical containing cells. Native controls distinguish geometry
and normal dependencies at the halo corner and exclude the next outside sample.
This tests the predicate; end-to-end normal-only edit invalidation is still needed.
Normals retain their previously documented trilinear-gradient discontinuities.

Native controls also reject a mesh assigned to the wrong owner, recover both
height/output allocation failures with empty normal output, and discard partial
normals after cancellation (256 samples evaluated). The normal fault controls
do not track process-wide leaks or qualify the entire engine's allocation policy.
