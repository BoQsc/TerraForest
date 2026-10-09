# Persistent native model-region catalog

`NativeModelRegionStore` owns a Windows directory for one model asset. Call
`open_store(absolute_directory, asset_id, recover_backup=false)` on a closed
instance, then publish TFMR packets from `NativeStaticBatch.capture_region`.
The directory must already exist. The store leases it exclusively until close;
it cannot be simultaneously opened by another block or model store owner.

The implementation composes the existing native region-store engine. Model
packet parsing, signed coordinate limits and blob limits are selected internally;
the public model facade does not expose block snapshot APIs. Block catalog
bytes remain unchanged. Model catalogs use a separate TFMC version-2 header
containing the SHA-256 of the configured asset identity. Both packet parsing
and catalog opening reject another asset, including an empty mismatched catalog.
Catalogs/checkpoint files retain the existing `.tfrc` names and immutable blobs
retain `.tfrg`; the encoded magic determines their type, not the filename suffix.

## Commit and retention contract

- `publish_region(packet, expected_checksum)` and `publish_regions(packets,
  expected_checksums)` require the current catalog version, or an empty checksum
  for a new region. Batches contain at most 64 packets and 64 MiB total payload.
  Validation completes before publication; stale or mixed-asset batches fail.
- Checksummed blobs are flushed and verified before the catalog commits.
  Existing immutable content is compared, never overwritten to hide corruption.
  Failed late writes may leave orphan blobs for bounded collection.
- `read_region`, `checksum` and `list_regions` address signed origin regions.
  Reads validate both the cataloged packet identity and the asset binding.
- `pin_checkpoint`, `checkpoint_regions`, `read_checkpoint_region`,
  `activate_checkpoint` and `release_checkpoint` preserve exact older catalogs
  through later edits/deletions. Current, backup and pinned versions retain their
  blobs; `collect_garbage(max_inspected)` limits directory inspection per call.
- Corrupt primary catalogs fail normal opening. Backup recovery is explicit and
  subsequent publication creates a new committed catalog. This does not repair
  corrupted blobs. Only one store owner is supported; this is not a distributed
  transaction or multiplayer conflict-resolution protocol.

Store methods are synchronous and serialized. Run them on an I/O owner, not the
render thread. The catalog retains the shared 65,536-region and 16-checkpoint
limits. Model blobs support the transfer format's 5,600,232-byte maximum.
No model I/O queue, metadata bootstrap or automatic world paging is enabled yet.
The catalog validates each region packet; it does not establish cross-region
placement-ID uniqueness or the collection-wide logical instance budget. Those
invariants must be checked by the future collection manifest/bootstrap layer.

## Evidence and remaining integration

`tests/model_region_store.gd` passes 28 checks with debug and release DLLs in
Godot 4.7.2 on the new host. It covers publication, a separate-process reopen,
conditional updates, asset/type separation, exclusive ownership, checkpoint
retention/activation, bounded collection, live unloaded-record restoration,
immutable-blob corruption and explicit catalog-backup recovery. The release
runner uses an isolated temporary project. Existing block region-store,
checkpoint and partial-storage suites pass after the shared-engine change.
Evidence: `docs/evidence/model_region_store/`.

These are short headless storage correctness checks, not interruption-at-every-
write, performance, memory, graphical or endurance qualification. Needed next:
collection manifest with IDs/bounds, metadata-only bootstrap, partial compound
save publication, bounded model I/O and history-aware admission/eviction that
preserves distant world representation. Main-world model storage remains fully
resident until these are integrated.

## Complete collection publication and reconstruction

`publish_snapshot(snapshot)` accepts a complete, asset-matching TFSI collection
snapshot and partitions it into TFMR region blobs natively. It publishes one
replacement catalog after writing/verifying the blobs. Regions absent from the
snapshot are removed, preserving demolition; unchanged content preserves the
catalog generation. This is authoritative replacement by the store owner, not
a conditional merge with concurrent gameplay edits. Capture order and latest
save selection remain the caller's responsibility. Incomplete collection
captures return empty bytes and are rejected. Late failures can leave orphan
blobs but do not publish an incomplete replacement catalog.

`read_checkpoint(checkpoint)` reconstructs the complete TFSI snapshot from a
pinned catalog, validating every blob, asset identity and global placement-ID
uniqueness. It rejects more than 4,096 catalog regions or 100,000 instances;
there is no partial success on corruption or duplicate IDs. Empty checkpoints
reconstruct a valid empty snapshot with the configured asset identity.

These synchronous full-collection operations are a compatibility save/load
path and a reference for future partial storage, not metadata-only loading.
They allocate resident maps and process every referenced record. The updated
43-check debug/release fixture includes a byte-exact 100,000-instance round
trip, disk reopen, reduced/empty saves, retained old checkpoints, malformed
snapshot rejection and cross-region duplicate-ID rejection. Evidence for this
stage: `docs/evidence/model_snapshot_catalog/`.

## Partial model storage

Capture `NativeStaticBatch.capture_storage_state()` on the collection owner
thread. Transfer its `resident`, `unavailable_keys` and `unavailable_checksums`
together to the I/O owner. The resident TFSI bytes intentionally exclude unloaded
records; they are not a whole-world snapshot. `capture_snapshot()` continues to
reject partial collections. Returned packed values do not mutate native state.

`NativeModelRegionStore.publish_storage_state(resident, unavailable_keys,
unavailable_checksums, checkpoint=empty)` commits the combined logical state.
The unavailable keys are sorted unique signed XYZ triples, disjoint from all
resident origin groups, with one 32-byte packet checksum per key. Each reference
must match the active catalog or the explicitly supplied pinned checkpoint.
Unknown/stale references reject the save instead of substituting another version.
An explicitly supplied checkpoint must exist. Loaded regions omitted from both
resident data and references are removed, preserving demolition.

Before any new blob writes, publication reads and validates unavailable packets
one at a time, checks global ID uniqueness against resident data and enforces
the combined 100,000-instance / 4,096-region bounds. Corruption rejects the save.
The catalog preserves unchanged unavailable blob references rather than
rewriting their transforms. Old pinned checkpoints remain unchanged. This is
an authoritative serialized save, not a merge protocol; callers must preserve
capture/commit ordering and checkpoint ownership.

This stage deliberately trades I/O for validated identity and capacity. It scans
all unavailable records and holds an ID set plus resident maps; it is not yet
constant-cost, dirty-only or metadata-only saving. Persistent identity manifests
are still needed to remove that read amplification. It must execute on an I/O
owner and is not suitable for a main-thread frame budget.

The expanded `model_region_store.gd` fixture has 63 checks. A partial save with
100,000 logical records and only 1,000 resident transforms preserves 99,000
unloaded records plus an exact resident edit. Other checks exercise signed
references, demolition, unchanged saves, disk reopen, older checkpoint fallback,
corrupt blobs, malformed/overlapping manifests and duplicate IDs. Evidence:
`docs/evidence/model_partial_storage`. These APIs are not yet connected to the
main-world compound archive, metadata bootstrap or automatic model pager.
