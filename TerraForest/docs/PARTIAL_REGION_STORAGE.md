# Native storage capture with unloaded regions

`NativeBlockWorld.capture_storage_state()` captures three values together on the
scene owner thread: `resident` (a TFBL encoding of resident chunks), sorted
`unavailable_keys` (packed xyz triples), and matching `unavailable_checksums`
(concatenated 32-byte packet digests). Transfer these values together to an I/O
owner. Caller mutation of returned packed values does not mutate the world.

This is a storage-state capture, not a standalone whole-world file. Its resident
bytes deliberately omit unloaded regions. The existing `capture_snapshot()` guard
is unchanged and still returns empty bytes while any region is unavailable.
Applications must not feed `resident` alone to the complete-snapshot save path.

`NativeBlockRegionStore.publish_storage_state(resident, unavailable_keys,
unavailable_checksums)` validates the resident snapshot and complete unavailable
manifest before publishing region files. Missing-region keys must be sorted,
unique, in range and disjoint from resident chunks. Every missing region must
exist in this store's committed catalog with exactly the expected digest, or in an
explicitly supplied pinned checkpoint (see METADATA_WORLD_LOADING.md). Without that
optional checkpoint argument, only the active catalog is accepted.
A stale or absent reference rejects the operation without changing the catalog.
Combined resident and unavailable regions remain capped at 65,536.

The next catalog consists of these verified unavailable entries plus the encoded
resident regions. Old regions absent from both sets are removed: this preserves
demolition of all resident cells in a region instead of resurrecting them on load.
Unchanged state avoids catalog revision churn. New blobs are written before the
catalog commits; late I/O failures can leave collectible orphan blobs using the
existing publication rules. Existing checkpoints retain their prior content.

Unavailable references are checked against committed catalog metadata, without
rereading every unavailable blob for every save. Missing/corrupt physical files
are still detected by region reads and checkpoint reconstruction. This method
does not repair external disk damage. An empty region must also be persisted
before unloading it if its digest will appear in a later storage-state capture.

The method is synchronous and serialized by the store mutex; call it from the
store's I/O owner. It is an authoritative replacement of that owner's complete
logical block state, not a concurrent merge protocol or multiplayer transaction.
Capture, resident parsing and region conversion still process all resident chunks;
this is not yet dirty-region delta saving. Transient chunk maps, snapshot bytes and
catalog metadata are not covered by the background queue's payload accounting.

Tests cover preserved unloaded cells together with resident edits, exact checkpoint
reconstruction, old checkpoint retention, resident demolition, malformed/overlapping
manifests, stale references, disk reopen and unchanged publication. The main world uses the storage envelope and archive integration
described in [PARTIAL_WORLD_ARCHIVE.md](PARTIAL_WORLD_ARCHIVE.md). Automatic paging
is not enabled by this change.
