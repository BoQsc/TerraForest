# Regional terrain storage

2026-10-23 implementation checkpoint. Native demand residency now uses the same
regional products in ordinary world loading. This is an active part of the world
rewrite, not a claim of complete long-run or rendered latency qualification.

## Authoritative representation

Compound world saves select a 40-byte `TFTR` version 1 terrain reference. Its
SHA-256 names an immutable `.tindex` in `<world>.trw.terrain/`. The index retains
seed, generator, revision, edit count, original page order, legacy exact blocks,
and region membership. There is no mutable sidecar pointer to the current world.
The outer compound root selects terrain and the other addons together.

Each 64 m region contains at most 64 original 16 m density/material pages.
Pages choose lossless sample runs, the engine's existing FastLZ codec, or a raw
fallback. This introduces no external asset or source license. Density values,
materials, lattice resolution and surface extraction are unchanged. Original page
order is retained, so expansion reproduces the exact native format 3 byte stream.
Legacy format 1/2 readers remain; the first migrated raw archive is retained as
the compound publication backup. New checkpoint saves require the updated reader
and their terrain sidecar.

Region records are packed in immutable files of at most 16 MiB. Each region has
its own SHA-256, pack identity, offset and bounded length. Selective reads read and
verify the requested region range; they do not decode the other regions in a pack.
The index is capped at 20 MiB, a region at 787,216 bytes, and coordinates, page
membership, counts, encoding sizes and legacy blocks are validated before use.
Missing or damaged authoritative data fails loading; it never falls back to the
unedited base field. Allocation failures that the engine reports are rejected.

Publication flushes and verifies new packs and index files before the compound root
changes. Existing immutable identities are verified and never overwritten. A failed
root publication leaves the previous root selected; interrupted immutable products
may remain unreferenced. Native world cloning/recovery and the Python compatibility
cloner include `.terrain`, and destination checks reject an orphan terrain sidecar.
Current/backup referenced products are retained. **Garbage collection and partial
pack compaction are still required; none is silently performed by this version.**

## CPU work and cache identity

Larger captures encode disjoint regions with at most half the reported logical
processors, capped at four. Small captures remain serial. The generation extension
admits one parallel field/storage batch at a time; a competing batch or failed
thread creation retains serial correctness. A setup-only one-worker mode verifies
identical checkpoint bytes. I/O and final root publication have one owner.

Derived mesh/cache identity now hashes the verified small terrain reference when
one exists. It agrees between save completion and reopen. Legacy raw snapshots
retain their existing hash path. Re-hashing an 81 MB expanded payload merely to
name the cache is unnecessary; a checkpoint already binds that content.

## Evidence and limits

See [retained checks](evidence/terrain_regional_storage/README.md). Native region
tests cover all three page codecs, exact reconstruction, bounded region reads,
unchanged saves, local edits, malformed membership, damaged/missing dependencies,
writer exclusion, failed root publication, backup selection, cloning and interrupted
publication recovery. Real source generation/reopen also passed and matched the
prior generated terrain and complete world signature.

The 2,048-excavation test has 6,612 edited pages and an 81,274,740-byte native
payload. Its terrain-only compound root is 103 bytes; initial terrain products are
about 19.36 MB. An unchanged save writes zero terrain files; a later local edit
writes a 127,043-byte pack/index pair. One matched sample measured approximately
235 ms parallel publication versus 317 ms serial, with exact byte equality. These
are scoped CPU/storage observations on the current laptop, not unbiased benchmark
estimates, whole-game performance, thermal, frame-time or endurance qualification.

The actual combined world's root also contains other addon state, so it is larger
than 103 bytes. Do not present the terrain-only fixture's root size as the entire
game-world save size.

## Required continuation in this rewrite

1. Dirty-page capture and checkpoint merging are now used by both asynchronous
   and shutdown compound saves. Native captures freeze only changed density/material
   pages, original key order, process-local page versions and legacy block bytes.
   A global 256 MiB admission budget bounds simultaneous pending captures. The
   baseline advances only after successful outer-root publication; later edits stay
   dirty. A load/reset invalidates old tokens even if revision values repeat.
   Reopen binds the verified checkpoint as the clean baseline. See
   [evidence](evidence/terrain_dirty_capture/README.md). Capture still scans page
   keys and copies legacy exact blocks; publication still verifies retained
   compressed regions. Eliminate unnecessary repeated history verification only
   with explicit immutable-file ownership/invalidation, corruption and recovery
   proof. Do not claim constant total save cost from the reduced sample copy.
2. Selective native page residency is integrated. The production loader mounts the
   verified regional checkpoint directly, retaining only its complete key catalog
   and legacy exact blocks. It no longer constructs an expanded terrain byte array.
   Intrusive LRU links give constant-time sample touches; eviction traverses only
   the bounded resident set, never historical page keys. Each cold miss decodes a
   verified 64 m region into one-region scratch and admits the requested 16 m page.
   Dirty samples and the footprint of an atomic edit cannot be evicted. Rejected
   admission rolls back new pages; only successful compound publication advances
   clean stamps. Edits newer than a frozen save remain dirty after acknowledgement.
   The default resident ceiling is still 16,384 pages, not increased. Native tests
   exercise smaller 16/32/1024-page budgets. The full catalog is bounded by the
   existing finite world's lattice (126 × 126 × 17 pages), independently of sample
   residency. Legacy whole-blob import/expansion retains its old capacity limits;
   larger histories must use the regional representation. A 2,112-addition fixture
   reached 16,896 authored pages with at most 1,024 resident pages and cold reopened
   under a 32-page bound. Density hits/normals/content identities and incremental
   checkpoint retention pass. See [evidence](evidence/terrain_residency/README.md).
   Required continuation: worker prefetch/admission for predictable first response,
   a rendered populated-world journey with history beyond the old cap, pressure
   from long unsaved edits, and the mining gate below. Demand faults are currently
   synchronous on the terrain worker, so bounded memory is not a latency guarantee.
   Dirty-only pressure rejects an edit when no resident slot can safely be freed;
   it must never discard an unsaved page or silently restore base terrain.
   A brand-new field also retains the old resident ceiling before its first
   checkpoint. Large offline plans need bounded unpublished checkpoint stages;
   add these before claiming generation of arbitrarily large authored layouts.
3. Add bounded retention-aware collection and pack compaction. First establish
   canonical/backup/in-flight reader ownership, then collect only products not used
   by any retained checkpoint. Close with interrupted collection, active readers,
   corrupt/missing manifests, backup recovery and storage-growth measurements.
4. Re-run the failed rendered mining-arrival gate and combined populated-world
   travel after paging/admission changes. Native edit arithmetic and small roots
   do not prove visible responsiveness or sustainable 1920x1080 at 60 FPS.
   The [coarse-owner replay](evidence/terrain_simplifier_links/README.md) now
   separates that cost: no sample faults during the expensive rebuild, and most
   native time in extraction/simplification of the visible 256 m owner. Preserve
   the unchanged response/gap gates; bounded local publication is required in
   addition to storage prefetch. The native scratch correction is not that closure.

These are immediate dependent work, not optional features or post-release deferrals.
The separately reproduced pending-lake shutdown and deleted-ID persistence defects
also remain open before broad persistence acceptance. Preserve accepted static water;
flow/spillage and water art changes are excluded.
