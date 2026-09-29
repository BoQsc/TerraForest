# Bounded native region reads through the world archive

`NativeRegionWorldArchive` now provides an optional persistent read worker using
its already-open `NativeBlockRegionStore`. It does not create a second catalog
owner or take another sidecar lease. Exact reads use the active-catalog/explicit
checkpoint selection described in METADATA_WORLD_LOADING.md and validate the blob
before returning it.

Start the service after archive acquisition with `start_region_reads(request_limit,
byte_limit)`. Defaults allow eight outstanding requests with eight worst-case byte
reservations. Count limits are 1–64. The byte limit is at least one reservation and
at most 128 MiB. Each accepted request reserves **2 MiB + 96 bytes**: the maximum
encoded region plus expected, checkpoint and returned checksum digests. Pending,
active and unread completed requests all retain their reservation until polling.
Dictionary/container overhead, catalog metadata, parser scratch, allocator overhead
and results retained by the caller after polling are outside this payload budget.

`request_region_read(region, expected_digest, checkpoint, epoch)` returns a unique
positive ticket or zero if the request is invalid, stopped or exceeds either
budget. The checkpoint may be empty, the expected checksum must contain 32 bytes,
and the opaque scene epoch must be nonnegative. The epoch is echoed, not interpreted
by the archive. Request digest values are retained using packed-array copy-on-write
isolation. Queue admission does not acquire the store's disk-I/O mutex.

`poll_region_reads(max_results)` returns up to 1–64 FIFO completions (default four)
and releases their reservations. Each carries `ticket`, `epoch`, `region`,
`expected_checksum`, `checkpoint`, and the store result's `ok`/`error`/`message`.
Successful reads also contain `bytes`, `checksum` and `generation`. Failed reads
remain explicit completions and must never be admitted as empty regions. The
caller must compare the returned epoch with its current scene epoch before
attempting native region restoration. The existing expected-digest handshake also
rejects an old packet when the scene now expects another version.

The read worker shares the store's mutex with publication and garbage collection,
so the file cannot be collected during its validated read. A queued version can
become unavailable before execution; that yields an error instead of a substitute
version. The worker never touches scene nodes or the world-root archive. Queue
request/poll/stat calls use a separate mutex that is never held during disk I/O.
Long saves can delay reads waiting for the store, so this is not a latency guarantee.

`stop_region_reads()` immediately closes admission and wakes the worker to drain
accepted requests. `join_region_reads()` waits for that drain. `release()` and the
destructor join before closing the store and root lease. These lifecycle calls can
block on an in-flight disk operation; they must not race each other or world-save
lifecycle operations. They belong at explicit start/stop boundaries, not per frame.

Completions remain pollable after release. Reacquiring an archive or restarting its
service requires all old completions to have been consumed. Tickets remain unique
across service/world restarts within the same archive object. Destructor shutdown
discards the drained completion containers as part of object destruction.

`region_read_stats()` reports queue lengths, active/running/stopping state,
outstanding/reserved values, configured limits and high-water marks. Accepted,
finished, rejected and worker-start counters accumulate for the object's lifetime;
high-water marks reset on each service start.

The test suite checks count/byte backpressure including unread completions, request
isolation, FIFO tickets and epochs, failure accounting, stale scene versions,
reacquisition, corruption, and 12 destructor cycles with queued reads. Its concurrent
workload runs 100 exact reads alongside 32 world publications and checkpoint
retirement. Evidence is retained in `docs/evidence/archive_region_reads`.

The interactive demo does not start this service yet. Native selection of nearby
regions, bounded scene admission, eviction of committed clean regions, predictive
travel loading and scene-epoch cancellation remain unfinished. This is a read
transport for that pager, not automatic world streaming or an endurance benchmark.
