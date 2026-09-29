# Native block-region disk catalog

`NativeBlockRegionStore` supplies persistent storage for the explicit block-region
transfer API. It is an independent Windows C++ RefCounted object in the structures
addon. It does not automatically evict buildings, replace the compound world save,
or store static-model placements. The demo still keeps authored regions resident.

## Ownership and use

Create an existing absolute directory and call `open_store(directory)`. The store
holds an exclusive Windows file handle for its directory lease until `close()` or
destruction. A second store cannot open the same directory concurrently. Methods
are synchronous and serialized by a per-instance mutex; use one caller-owned I/O
worker and exchange immutable packets with the scene thread. Calling methods,
including status methods, on the scene thread can wait for ongoing I/O.

1. On the scene thread, obtain `blocks.capture_region(region)`.
2. On the I/O worker, call `publish_region(packet, expected_checksum)`. Empty
   expected bytes mean the region must not exist; otherwise supply its current
   32-byte catalog checksum. Check the returned `ok` before continuing.
3. Return the original packet and successful acknowledgement to the scene thread.
   `blocks.unload_region(packet)` rejects an intervening edit. If it rejects,
   retain the live region and persist its newer version before trying again.
4. Read using `read_region(region)` on the worker, check `ok`, then restore the
   returned `bytes` on the scene thread through the block-world transfer API.

`publish_regions(packets, expected_checksums)` commits 1–64 distinct regions in
one catalog revision, with at most 64 MiB of packet input. All packets and expected
versions are validated before writes begin. `remove_region(region, expected)`
removes a catalog reference conditionally. It does not unload scene data.
`list_regions()` returns sorted packed xyz triples; `checksum(region)` returns
the digest or empty bytes for an absent entry. Status dictionaries expose `ok`,
`error` and `message`. Reads also return packet bytes, checksum and generation.
An unchanged publication verifies its blob without advancing the revision.

## Files, publication and recovery

The directory contains `catalog.tfrc`, its previous revision `catalog.tfrc.bak`,
the lease file `.region.lock`, and immutable `blobs/<digest>.tfrg` files. The digest
is the validated packet's trailing SHA-256. Region blobs are limited to 2 MiB;
catalogs hold at most 65,536 entries and are read with a 4 MiB bound. Metadata is
rewritten once per committed batch, so commit work grows with catalog size.

Publication writes uniquely named pending files, flushes and reads them back,
publishes all required blobs, preserves the previous catalog, then replaces the
primary catalog last. A new empty store commits its initial catalog before any
blob publication. Failed late writes can leave unreferenced blobs, but cannot
expose a partially published batch through the catalog. Existing hash-named blobs
must match exactly; corrupt files are never silently overwritten.

Default opening never silently rolls back a damaged or missing primary. The
failure reports whether a valid backup is available. Explicitly opening with
`recover_backup=true` selects that backup even when the primary is valid. The next
publication preserves the selected recovery version and advances beyond both
valid observed generations. This is not a monotonic counter across unknown,
corrupted history; concurrency checks use content digests. If both catalogs are
missing but region blobs remain, opening refuses to infer a new empty world.
Blob integrity is checked on read, rather than scanning every blob during open.

Windows file flushing and rename behavior follows Microsoft's
[FlushFileBuffers](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers)
and [MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)
APIs. Testing used ordinary local directories. Physical power-cut durability,
network filesystem behavior and platform-wide long-path support are unverified.
The cooperative lease and observed-catalog checks do not protect against arbitrary
outside processes modifying files between operations.

## Bounded maintenance

`collect_garbage(max_inspected)` inspects 1–256 directory entries per call and
retains its enumeration cursor between calls. It preserves every blob referenced
by either the current or backup catalog. Only correctly named, validated,
unreferenced region packets are eligible for deletion. Unknown files, corrupt
packets, directories, reparse points and pending files are preserved. Deletion is
best effort; `complete` means enumeration finished, not that every deletion
succeeded. Publication resets the cursor.

Garbage collection refuses selected recovery before publication, an invalid
existing backup, or out-of-owner catalog changes. Publication also detects
changes to the catalog files observed by the owner. Explicit [catalog checkpoints](BLOCK_REGION_CHECKPOINTS.md) now retain additional
versions beyond the active catalog and one backup. Whole-world root integration
is still required.

## Format and validation

The original TFRC v1 layout contains the eight bytes `TFRC\1\0\0\0`, a little-endian u64 generation,
a u32 entry count, then sorted 48-byte entries: three signed 32-bit coordinates,
32 digest bytes and a u32 blob size. A final SHA-256 covers all preceding bytes.
The total is 52 + 48 × entry count bytes. New writes use TFRC v2 with the same
layout and required checkpoint-retention metadata; current readers accept v1/v2.
See the checkpoint compatibility rules before accessing a store with older builds. Generation is 1 through INT64_MAX.
Duplicate, unordered, out-of-range and malformed entries are rejected even with
a recomputed checksum.

The 65-check suite passes with debug and clean release DLLs. It covers real files,
competing owners, stale updates, atomic batches, corrupt/missing catalogs and
blobs, explicit backup selection, bounded collection, worker-thread ownership,
fresh-object and separate-process reopen, and a later-blob write failure that
leaves the catalog unchanged and the earlier orphan collectible. Evidence is in
`docs/evidence/block_region_catalog`. These tests do not measure full-capacity
throughput, multi-hour endurance or actual process/power interruption.

The [native background I/O queue](BLOCK_REGION_IO.md) now bounds requests and
unread completions on one persistent worker. Automatic paging still requires a
residency policy, catalog-aware world roots and model-region storage. The existing
whole-world save guard remains necessary whenever block regions are unloaded.
