# Static-model checkpoint metadata

`NativeModelRegionStore.read_metadata(checkpoint)` returns a checksummed TFMD v1
manifest for a pinned model checkpoint. `NativeStaticBatch.restore_metadata`
replaces its scene records with unavailable regions and reserved IDs, without
installing instance transforms, render batches or physics bodies. Exact TFMR
packets are subsequently admitted through the existing `restore_region` path.
Full snapshot capture remains unavailable until all missing regions are loaded;
partial storage captures remain saveable through the model catalog.

The manifest binds asset and checkpoint, sorted region coordinates, exact packet
digests, ordered IDs and nine absolute basis-component maxima per region. IDs
must be globally unique and positive. Limits remain 100,000 logical placements,
4,096 regions and 1,144,272 encoded metadata bytes. The decoder rejects malformed
lengths, invalid coordinates, ordering, duplicate IDs, nonfinite/negative basis
values, mismatched assets and damaged checksums before changing scene state.

Translation is bounded by the known 32-metre origin region. Basis maxima bound
the transformed extent of the current registered mesh or compound collision
prototype, including reflections, scaling and shear. Bounds round outward when
converted to single precision. This intentionally overestimates occupied space
until exact records arrive; it keeps collision readiness and vegetation exclusion
conservative even for objects extending well outside their origin region. Asset
and collision reconfiguration remain blocked while regions are unavailable.

## Cache and worker ownership

Manifests are derived files beside pinned catalogs:
`checkpoints/<checkpoint SHA-256>.tfmd`. The first request reads and validates
each referenced packet individually, computes bounds and verifies global ID
uniqueness. It never assembles the complete collection of transforms. A valid
cached manifest is checked against the requested asset, checkpoint and catalog's
region keys/digests, then returned without reading region blobs. Missing or
corrupt caches regenerate from authoritative data. Cache writing uses verified
temporary files and atomic replacement; inability to cache does not invalidate
successfully generated metadata. Releasing a checkpoint also attempts to remove
its derived manifest.

`NativeRegionWorldArchive.request_model_metadata(asset, checkpoint, epoch)` runs
this operation on the archive's shared region worker. Results use
`poll_model_region_reads`, with `operation="metadata"` and the existing ticket,
asset and epoch fields. They share the conservative model request reservation
and global queue limits. The direct store method is synchronous and belongs on
an I/O owner. Cold generation can delay later reads in the shared FIFO; it is
not preemptible. Scene installation still parses/reserves all IDs, so its cost
is proportional to logical object count.

These are integrity-checked local derived caches, not authenticated multiplayer
messages. A cache hit defers detection of missing/corrupt region blobs until
those regions are requested; failed admission keeps them unavailable. Parser
scratch, map/set allocation overhead and caller-owned buffers are outside queue
payload accounting. Reserved IDs remain proportional to logical object count;
zero resident transforms is not zero total model memory.

## Verification and integration boundary

`tests/model_region_metadata.gd` checks 100,000 placements across 100 regions,
zero-transform bootstrap, one-region admission, partial saves, conservative
collision/exclusion bounds, byte-exact full reconstruction, invalid manifests,
cache reopen/regeneration, duplicate source IDs, corrupt blobs and retirement.
`tests/region_archive_reads.gd` checks delivery through the shared archive worker.
Evidence: `docs/evidence/model_metadata`.

The main-world decoder still loads full model snapshots. Automatic model-region
selection, budgeted admission/eviction and coordinated paging lifecycle must be
connected before switching the main world to metadata-only model startup.
This test establishes storage and bootstrap correctness, not game FPS, total
process-memory savings, frame-time bounds or thermal qualification.
