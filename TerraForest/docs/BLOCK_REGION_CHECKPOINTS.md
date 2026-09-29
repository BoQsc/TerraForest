# Persistent block-region checkpoints

The region store now retains explicit catalog checkpoints independently of its
active and backup revisions. A world-save coordinator can pin the building state
before publishing a root save, then retain that pin for as long as any save or
backup references it. Subsequent region edits and blob collection preserve the
checkpoint's exact versions. This supplies retention; integration with terrain,
water, models and the compound world-save transaction is still unfinished.

## Native API

`NativeBlockRegionStore` adds these synchronous, worker-compatible methods:

| Method | Result |
| --- | --- |
| `pin_checkpoint()` | Status plus 32-byte `checkpoint` identity for the current catalog |
| `list_checkpoints()` | Sorted concatenated 32-byte identities |
| `checkpoint_regions(checkpoint)` | Status, packed xyz `keys` and checkpoint generation |
| `read_checkpoint_region(checkpoint, region)` | Validated historical packet, checksum and generation |
| `activate_checkpoint(checkpoint)` | Publishes the checkpoint's complete region index as a new active revision |
| `release_checkpoint(checkpoint)` | Removes retention for that identity; old blobs become eligible for normal collection |

Pinning the same catalog is idempotent. It does not increment an external save
reference count: if two world roots share the identity, the caller must keep the
pin until **both** roots and their backups cease referencing it. At most sixteen
distinct checkpoints may be pinned. Reaching capacity rejects a new pin rather
than evicting an older save. Release only explicitly unreferenced checkpoints.

Checkpoint reads do not change the active catalog. Activation replaces the active
index, retains the prior active catalog as backup through the ordinary publication
path, and advances beyond valid known active, backup and checkpoint generations.
It does not restore scene nodes, terrain, water or models. Blob integrity is checked
when read; pinning/activation validate catalog metadata but do not rescan all region
blobs. Missing/corrupt data remains an explicit read failure, never inferred air.

All six methods also exist on `NativeBlockRegionIO`, returning normal queue tickets.
Completion operations are `pin`, `pins`, `checkpoint_index`, `checkpoint_read`,
`checkpoint_activate` and `checkpoint_release`. The list result uses `checkpoints`.
Pin/list reserve 32/512 bytes; checkpoint index reserves 2,883,616 bytes for xyz
keys, digests and the input identity. Checkpoint reads reserve their maximum
packet output plus the 32-byte identity; activation/release reserve 32 bytes. A checkpoint
read therefore needs more than a minimal 2 MiB queue budget. Existing FIFO,
backpressure, result ownership and shutdown rules apply.

## Publication and retention

An immutable `checkpoints/<identity>.tfrc` holds the full catalog. The identity is
SHA-256 of the complete catalog file. Creating a pin flushes and verifies this file,
then atomically publishes the small `checkpoints.tfcp` retention index. Only after
that succeeds does the in-memory reference set change. A failed index replacement
can leave an uncommitted checkpoint file; retry accepts it only if bytes match.

Release publishes the new retention index before removing the in-memory reference
and attempting deletion of its checkpoint file. `checkpoint_file_removed` reports
that best-effort deletion separately. A committed release can therefore succeed
while its unreferenced catalog file remains. Uncommitted/undeleted checkpoint files
and pending files are not currently collected automatically; disk-quota and orphan
maintenance remain future work. They cannot be read or activated as pinned saves.

The TFCP v1 index has eight magic/version bytes `TFCP\1\0\0\0`, a little-endian u32
count, sorted unique 32-byte identities, then SHA-256 over the preceding bytes.
Its size is 44 + 32 × count, at most 556 bytes. On open, every referenced checkpoint
file is bounded, hashed and parsed. Corrupt/missing retention metadata prevents
opening, including explicit active-catalog backup recovery; it is never silently
replaced with an empty set. A stopped initialization that published a v2 catalog
but failed to initialize its retention index also fails closed on reopening.

In memory, checkpoint catalogs and per-blob pin counts are built on open and
updated on pin/release. Collection checks this retained index rather than parsing
every checkpoint for every inspection step. Ordinary catalog publication does not
rebuild the pin index. Shared blobs remain protected until their last checkpoint
reference is released, or while still referenced by active/backup catalogs.
Observed retention-index changes outside the owner stop publication and collection.

The maximum is sixteen catalogs of up to 65,536 entries each, plus a unique-blob
reference map. This metadata, parsing scratch and allocator overhead are outside
the I/O queue payload budget. Pin/open/release cost scales with retained entries;
these operations belong on the native I/O worker. Full-capacity throughput and
memory usage have not yet been measured.

## Compatibility

New catalogs use **TFRC v2** with the same entry layout as v1 and require retention
metadata. Current readers accept both versions. A valid active v1 catalog can
initialize an empty retention index only when no checkpoint files suggest missing
metadata. First pinning upgrades the active catalog before exposing any pin.
Ordinary subsequent publications also write v2.

Older native store builds reject normal opening of v2, preventing their unaware
garbage collector from discarding pinned data. Do not use an older build to force
recovery from a legacy v1 backup in a checkpoint-enabled directory. This format
change concerns the new standalone region store, not existing `.trw` world saves
or the TFRG region-packet format.

## Validation and remaining integration

All 46 checks pass using real local files with debug and clean release DLLs. They cover historical
retention through multiple publications and collection, separate-process reopen,
activation, capacity, shared blob references, malformed/missing/corrupt metadata,
legacy upgrade and queued operations. A Windows open-file obstruction forces
retention-index replacement to fail after the checkpoint file exists; neither
pin creation nor release changes committed references on failure. Reports and
build fingerprints are retained in `docs/evidence/block_region_checkpoints`.

These tests do not certify physical power-loss durability or multi-hour endurance.
The application must still coordinate checkpoint creation with exact terrain and
other component state, persist checkpoint identities in world roots, retain root
backups, and release pins only after those roots are retired. The demo has not
enabled automatic authored-region eviction or catalog-based whole-world saving.
