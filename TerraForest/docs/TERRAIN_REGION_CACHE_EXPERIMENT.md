# Reconstruction-region cache experiment

## Decision: keep experimental, do not enable in gameplay

A bounded cache can avoid most repeated surface extraction, but does not bound
the rest of a large patch rebuild. The release test's warm 256 m patch after
2,176 mining commands still averages **189.1 ms native time**, before worker
queueing, scene publication or collision integration. That already exceeds the
integrated test's 150 ms edit-publication target. Cold and eviction-heavy builds
are slower than the uncached path. This experiment does not qualify the terrain
foundation, prove 60 FPS, or justify scaling up city content.

Normal terrain requests remain command 1, with the cache disabled. Command 20
is an experimental native path used by the test. No render-quality reduction or
new distance cutoff is involved.

## Mechanism and scope

The Surface Nets extractor is separated from connectivity generation. Command
20 retains raw surface representatives in 16×16 m horizontal regions spanning
the current field's full vertical extent. Each global cell has one owner;
representatives are reassembled in the original z/x/y order. Connectivity,
simplification, legacy blocks, shading, materials, mesh encoding and collision
encoding then use the same implementation as command 1.

The cache has 512 slots and a default 32 MiB payload-capacity ceiling. It uses
least-recently-used eviction, counts allocated list capacity rather than live
vertices, and bypasses a region larger than its budget. Metadata occupies
53,840 bytes in this build. The measured edited 256 m working set uses 289 slots,
8,640,760 payload bytes and 8,694,600 bytes including metadata. Allocator overhead,
temporary extraction/assembly, final meshes, lighting caches and authoritative
world data are outside this ceiling. This is not a whole-process memory bound.

Edits mark intersecting reconstruction regions dirty using conservative sample
bounds. The corner excavation test invalidates four of 289 regions and reuses
the other 285. Lighting remains revision-dependent and is recomputed through the
existing shading path. Save data excludes this cache; successful load, reset and
surface-style changes release it. Ownership remains inside the native world's
serialized worker access. Cancellation uses the existing atomic owner epoch.

This representation is still specific to the current finite world and vertical
range. It is not a sparse unlimited-world representation, independent region
LOD, or a replacement for the existing full-patch simplifier.

## Adversarial checks

`tests/terrain_region_cache.gd` runs 293 assertions in each debug/release build:

- Exact encoded mesh bytes after the reply header, including positions, indices,
  normals, materials, shading and collision faces; caves, world edges, unaligned
  requests, sizes 16 through 256, and all four supported LOD steps are exercised.
- 96 mixed sphere/box additions and excavations crossing region boundaries and
  several depths; 94 commands change terrain.
- Replay of the retained integrated mining workload using its original seed
  1703: 2,176 commands, 2,164 with actual changes. A 90% change requirement prevents
  an incorrectly seeded empty-space replay from passing as a useful workload.
- Warm reuse, local invalidation, distant edits, legacy blocks, smooth style,
  snapshot independence, reload/reset, malformed diagnostic configuration.
- Nine separated 128 m patches exceeding the slot limit; revisit after eviction.
- A 64 KiB payload budget, immediate eviction after shrinking, oversized-region
  bypass, and repeated 256 m queries that deliberately thrash the cache.
- Stale-epoch rejection and cancellation during a cold native build, followed by
  exact comparison using the partially populated cache. Release cancellation
  joined in 0.163 ms in this run; this is one observation, not a latency percentile.

The existing legacy bridge comparison also passes: seven baseline checks,
31 debug checks and 31 release checks, with matching saved field/snapshot/mesh
fingerprints. This checks the default mesher refactor against the retained
published DLL rather than comparing only two paths sharing new code.

Byte equality demonstrates preservation of current geometry, not that the
original geometry is free of every seam, topology or collision defect. Allocation
failure injection, peak native allocation tracking, exhaustive field fuzzing and
long-duration leak testing remain unqualified.

## Matched release measurements

Godot 4.7.2 Steam, native release DLL, seed 1703, patch origin (1280,1280), size
256, step 8. Headless native tests intentionally measure no GPU or frame rate.
Any subsequent graphical acceptance test must remain 1920×1080 fullscreen at
full render scale. Matching queries alternate order; comparison and report
serialization occur outside timed intervals. Lighting caches can be warm even
when reconstruction is cold. Timing includes native encoding and bridge return.

| State | Pairs | Uncached mean ms | Cached mean ms | Finding |
|---|---:|---:|---:|---|
| Fresh cold reconstruction | 1 | 197.0 | 243.8 | 24% slower |
| Warm, before/after one local edit | 5 | 223.8 | 146.5 | 35% faster |
| First rebuild after local edit | 1 | 213.0 | 149.4 | 30% faster, virtually no end-to-end budget left |
| Warm after retained mining workload | 3 | 250.3 | 189.1 | 24% faster, still too slow |
| Retained edits, 64 KiB thrashing | 3 | 272.6 | 342.3 | 26% slower |

For the warm retained-workload rows, extraction/connectivity falls from 98.6 to
28.8 ms. Cached simplification still averages 107.3 ms and shading 48.3 ms. The
improvement is useful evidence of locality, but the dominant remaining work is
still proportional to a large patch. Cold region halos, assembly/sorting and
eviction bookkeeping add cost. Increasing cache size can mask misses in a small
scene; it cannot establish cold-travel performance or general scaling.

These are small matched samples, with visible timing variability, not statistically
qualified percentiles or a universal speedup claim. Raw samples include the first
cold retained-workload pair, which is excluded only from the explicitly **warm**
table row. No slow samples are dropped within a stated group.

## Next architecture gate

Before adoption, reconstruction, simplification, lighting dependencies and
publication must have independently bounded work. A region solution needs
cross-region surface/LOD correctness and a distant render representation that
does not trade one huge rebuild for thousands of draws. Compare cold travel,
reversal and saturated working sets alongside local edits. Re-run the integrated
mining suite after any runtime adoption; these native results cannot substitute
for it. Keep the other primitive pressure rows in `FOUNDATION_QUALIFICATION.md`
unqualified until their own evidence exists.

## Reproduce and evidence

```text
python tools/build_native.py --addon volumetric_terrain --target all
python tools/validate.py --test terrain_region_cache --timeout 180 --godot PATH
python tools/test_native_release.py --addon volumetric_terrain --test terrain_region_cache --godot PATH
python tools/test_terrain_bridge.py --godot PATH
python tools/qualify_terrain_region_cache.py
```

The last command **exits 1 on this implementation**, independently of the green
correctness suite. It rejects the observed 411.495 ms maximum native build and
the cold/undersized-cache regressions. Its provisional adoption gates require
every observed native build to fit the whole 150 ms edit budget and cold/thrashing
means to remain within 5% of the uncached path. Fitting the entire budget is only
a necessary condition: a production component needs room for the remaining work.
These small-sample gates reject obvious problems; they are not statistical
performance certification. Thresholds are not relaxed to make this experiment pass.

`docs/evidence/terrain_regions/` retains debug/release reports and logs, the bridge
comparison, and a manifest of source, fixture and DLL SHA-256 hashes. The parent
revision is recorded separately because the evidence is committed with the
implementation.

Experimental protocol: command 20 takes command 1's patch arguments and optional
epoch. Command 21 returns nine u64 values: hits, misses, evictions, invalidations,
entries, payload capacity bytes, budget, metadata-plus-payload bytes, oversized
bypasses. Command 22 takes a u32 budget from 65,536 through 33,554,432 bytes; budget
configuration is derived state and resets with the cache. These diagnostics are
not a stable public addon contract.
