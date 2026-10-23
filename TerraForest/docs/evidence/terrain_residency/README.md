# Selective native terrain residency

2026-10-23. This implements a storage/residency requirement of the world rewrite.
It does not establish completed generation, accepted world art, instant loading,
mining first-response latency, long-run FPS, or laptop thermal headroom.

Ordinary checkpoint loading previously expanded all edited pages into a single
byte array, then copied them into the native field. It now mounts the authenticated
regional index directly. The full authored key/order catalog is separate from
resident density/material samples. Native sample access, meshing, normals,
visibility, content keys and the experimental immutable sampler all use the same
page-access boundary. Missing or damaged authoritative data rejects a read; it is
never replaced with the unedited base field.

The native terrain worker owns the store and intrusive resident LRU. Hits move an
existing link without allocating or scanning history. Cold faults verify/decode a
single 64 m product and retain one decoded region as scratch; only the requested
16 m page becomes resident. Page eviction inspects at most the resident budget.
The default sample ceiling remains 16,384 pages, exactly the earlier ceiling.
The authored metadata limit follows the finite 126 × 126 × 17 world lattice;
this is not a resident-cap increase. Smaller budgets are available to native
setup/tests. Legacy full-blob import/expansion keeps its old limits.

Dirty samples cannot be evicted. An atomic edit pins its footprint before staging
and committing, and failed admission retires any newly allocated pages without
changing density/material/revision. Durable compound-root acknowledgement advances
clean stamps. A newer edit during publication remains dirty; the pager advances
its backing reference only to the durable checkpoint. Capture copies only dirty
samples and retains full catalog order, so evicted history participates in the
existing incremental regional publisher.

## Evidence

- `terrain_residency.json`: 549-page generated-field fixture mounts with zero
  sample pages. Distributed density hits/normals, three exact mesh packets,
  byte-exact serialization, dirty capture/save/reopen, newer-edit pinning,
  oversized edit rejection, corrupt cold dependency rejection and recovery pass
  with a 16-page resident bound.
- `terrain_residency_capacity.json`: 2,112 independent additions produce 16,896
  authored pages, beyond the old total-history ceiling. At most 1,024 pages
  (12 MiB of density/material samples) stay resident. Fresh ownership reopens
  under a 32-page bound (384 KiB), with 33 distributed cold density/normal probes,
  earliest/latest edits and the exact mesh-content identity retained. The complete
  checkpoint products verify and an unchanged capture copies no sample data.
  This finite synthetic empty-field fixture is not populated-game travel.
- `terrain_edit_atomicity.json`: unchanged pre-correction field/receipt hashes,
  512 allocator-fault combinations, 224 forced failures, no allocation leaks.
- `checks/`: dirty captures, compound publication failure/corruption protection
  and asynchronous publication/query/reload/shutdown ordering retain their passes.
- `source_generation/`: actual one-child Generate → Load → Play preparation,
  native binary verification, root-last publication, photographs and baked maps.
- `source_reopen.json`: full generated game opens read-only with native paging,
  loading 298 of 479 edited pages at playable admission. All four map layers hit
  cache, terrain patches stay zero, and the canonical root remains unchanged.
  Rendered world/map images were inspected. Repeated buildings/landscape remain
  visually unaccepted; these images establish integration, not world quality.
- `build_*`: debug/release terrain libraries built with the pinned Zig and
  prebuilt godot-cpp. No godot-cpp source was rebuilt.
- `pack/`: explicit exported PCK uses the production generation coordinator,
  publishes a new connected world, then opens the complete game read-only with
  native paging and all four cached map layers. The external harness supplies
  assertions only; game scripts/assets/libraries come from the PCK installation.
  This is same-machine explicit-PCK coverage, not clean-machine release proof.
- `mining/`: current generated-checkpoint held-mining rerun still fails. The first
  burst capture-to-draw p95 is about 272 ms; the second is about 73 ms. Maximum
  visible gaps are about 332 and 188 ms, so both gap gates fail. Frame p99 remains
  below 20 ms and there are no frames above 50 ms.
  This uses the actual mounted generated world, unlike the older fresh generator-1
  fixture; those different worlds are not a controlled before/after regression
  comparison. Bounded residency must not be reported as fixing mining response.

Timings in raw reports are scoped observations, not controlled speedup estimates.
Other navigation checks ran headlessly in a separate checkout during some runs;
do not use these observations to claim isolated CPU/thermal performance.

## Retained failures

`retained_failures/` includes a parse error from a shadowed fixture variable and
the initial large-history comparison that incorrectly compared revision fields
from different edit times. The corrected comparison checks hits, normals and work
results while allowing the expected revision advance. It also includes two
generated-world cache checks performed across native DLL rebuilds: gameplay opened
but rasters rebuilt. Cache compatibility intentionally includes the exact DLL
hash; creation/reopen with an unchanged binary subsequently hit every map layer.
These failed runs are not accepted passes.

The first packaged check tried to load a test script excluded from the production
pack. The corrected check calls the actual runtime coordinator. Its wrapper first
reported failure because it also read the preceding attempt's stale `engine.log`;
the current generation log, ready status, canonical publication and fresh packaged
reopen prove the actual run succeeded. Both original wrapper results are retained
with an explicit current-log evaluation; no failed diagnostics were deleted.

## Required continuation

1. Demand reads currently block the existing terrain worker on file access and
   bounded region decoding. Add native targeted prefetch/admission and measure
   cold arrival response; do not infer a latency improvement from bounded memory.
2. Repeat populated rendered travel/mining with authored history beyond the old
   cap and under resident pressure. Retain distant edited geometry, actual tools,
   saving and fresh-process reopen. The synthetic capacity fixture is only its
   short correctness prerequisite. Re-run the failed 150 ms first-visible gate.
3. Long unsaved dirty pressure still needs explicit gameplay admission/recovery
   evidence. If every slot is pinned, reject safely; never evict unsaved samples.
   Brand-new fields retain the original ceiling before their first checkpoint;
   offline plans exceeding it need bounded unpublished checkpoint stages as part
   of generation. The periodic-checkpoint capacity test does not prove that case.
4. Retention-aware collection/pack compaction needs canonical, backup, in-flight
   capture and active-reader ownership before deleting any authoritative product.
   Repeated index verification/key scans and legacy block copies remain costs.
5. Complete the generator/POI/options, compute-benefit, world visual and populated
   runtime requirements in WORLD_WORKFLOW_REDESIGN.md. Keep static water accepted;
   flow/spillage and further water art work are excluded.
