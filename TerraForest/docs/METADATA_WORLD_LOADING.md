# Opt-in metadata-first building loads

The native region archive can now open a building checkpoint without reconstructing
all its block cells. `configure(archive, structures_codec, true)` selects metadata
loading before acquisition. The default remains complete reconstruction.

For a published TFSR root, metadata mode reads the pinned catalog and returns
sorted region keys and exact packet digests with an empty resident TFBL snapshot.
Model records remain fully restored. Older TFSB roots still load as complete
snapshots and migrate to checkpoint roots on their next successful save.

The transient structures envelope is TFSQ version 1: the ordinary structures
header/model records/SHA-256, with a block payload consisting of a 32-byte fallback
checkpoint ID followed by the existing TFSP storage payload. This is a worker-to-scene
and scene-to-worker envelope; published world files still use TFSR references.
Ordinary snapshot/reference decoders reject TFSQ. Storage-aware validation checks
the entire envelope, nested blocks, unavailable manifest and model asset bindings.

`NativeBlockWorld.restore_storage_state(resident, keys, checksums)` validates both
maps before replacing either. It rejects malformed, duplicated, unsorted,
out-of-range or overlapping entries. It uses the ordinary restore invalidation
path to replace cells, reset history/cache state and invalidate outstanding bake
tickets. A single change signal observes the fully replaced state. Unavailable
regions continue to block editing and walking readiness; they are not empty space.

`structures_world.restore_storage_snapshot()` accepts either a complete bundle or
a validated storage envelope. It restores model collections and retains the
fallback checkpoint in subsequent partial captures. Complete restoration clears
that checkpoint and the separate partial cache. The original `restore_snapshot`
and `capture_snapshot` retain their complete-world contract.

Register the opt-in path before starting terrain:

```gdscript
persistence.register_component("structures", structures.capture_storage_snapshot,
    structures.restore_storage_snapshot, structures.snapshot_validator(),
    structures.empty_snapshot())
persistence.enable_region_structures(true)
persistence.attach(terrain)
```

This requires a caller that admits regions and handles unavailable/error states.
The interactive main demo retains full loading until automatic admission is
connected. Merely turning on metadata mode will not display unloaded buildings.

## Exact versions after interrupted publication

A failed world-root replacement can leave the active region catalog newer than
the published checkpoint. A metadata-loaded scene must preserve the latter.
The store's `publish_storage_state` accepts an optional fallback checkpoint ID.
Each unavailable reference first needs an exact key/digest match in the active
catalog. Otherwise it must match that explicitly named, still-pinned checkpoint.
Without a checkpoint argument, the previous active-catalog-only contract remains.
Unmatched versions reject publication before new region blobs are written.

The fallback does not keep an old checkpoint pinned forever. After later saves
retire it, exact versions still present in the active catalog remain valid. If
neither catalog can supply the expected version, the operation fails. This is an
authoritative single-owner snapshot protocol, not concurrent edit merging.

`read_storage_region(region, expected_digest, checkpoint)` on the store/archive
uses the same active-then-explicit-checkpoint selection. It validates the selected
blob and returns an error for missing/corrupt content or unavailable versions.
This synchronous API is for the archive owner, not a gameplay-frame call. The
archive now provides a bounded background queue (see ARCHIVE_REGION_READS.md).
Automatic scene admission must still compare epochs and reject stale completions.
Acquire/release must not race archive operations.

## Bounds and evidence

Metadata loading supports the existing 65,536-region catalog bound independently
of the 2,048-resident-chunk bound. Each admitted region is still limited to 64
chunks and 2 MiB encoded bytes. The 64 MiB structures envelope bound, model limits
and immutable asset registry remain. Catalog metadata and model records are read
at load; distant block payloads are read only when requested. Consequently damaged
distant blobs need not fail initial metadata loading, but their region reads must
fail and the scene must keep those regions unavailable.

Tests cover atomic replacement failures, legacy interface separation, checkpoint
identity, root replacement failure, exact historical reads, saving after fallback
pin retirement, corrupted blobs, and a 2,112-chunk/33-region checkpoint. That fixture
loads zero resident chunks, admits one 64-chunk region, and saves while 32 regions
remain unavailable. A real terrain worker exercises three startup/shutdown cycles
with static model identity and resident edits preserved. Evidence is retained in
`docs/evidence/metadata_world_load`.

Automatic paging, bounded scene admission, predictive loading, model-region
storage, delta capture, peak-memory measurements and long-run endurance are still
unfinished. The fixture proves removal of the full-reconstruction startup limit
for this opt-in path; it is not a large-city performance or multiplayer benchmark.
