# Bounded density reuse for candidate normals

The optional density-reuse path retains three tagged horizontal sample planes.
Each entry stores density and its absolute Y coordinate; modulo collisions
recompute the sample rather than returning data from another layer. This bounds
scratch independently of mesh height and remains correct for reordered vertices.
The cache belongs to one synchronous call against an immutable World.

Including column heights, scratch payload is `28 * (size + 2)^2` bytes:
32,368 bytes for 32 m and 9,072 bytes for 16 m. Normal output and allocator
overhead are additional. All scratch is destroyed before returning. This reuses
density within the normal pass; it does not yet reuse the geometry sampler.

Run `python tools/probe_terrain_tetra.py`. The retained
[report](evidence/terrain_candidate_normal_density/terrain_tetra_probe.json.gz)
has 53 passing checks. All 75 paired fixture outputs match the scalar reference
exactly. Native controls also reverse vertex order and inject failure into all
three allocations (heights, density entries, output), leaving no tracked buffers.

The retained 32 m cave case requests 167,024 samples but evaluates only 13,259.
Its paired median is 4.9248 ms versus 16.186 ms for height-only caching. An earlier
run measured 3.8815 versus 12.3185 ms; timing variation is visible and neither run
qualifies integrated latency or FPS. The reduction is useful but the remaining
whole pipeline, not this isolated pass, must determine runtime acceptance.

The scalar and cached paths share gradient arithmetic, while sample lookup is
independent. Existing exact partition normals and immutable geometry controls
remain in place. The positive normal sample halo is unchanged. Real normal-only
edit invalidation, world-edge normal fixtures, material packets, visual acceptance
and runtime integration remain outstanding. The opt-in candidate is not linked
into gameplay and does not establish the requested full-world performance.
