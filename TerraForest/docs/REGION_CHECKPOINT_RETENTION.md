# Checkpoint retention for asynchronous world reads

The region world archive now protects existing checkpoint pins needed by accepted
reads, plus explicitly leased versions held by scene/paging code. Previously
cleanup considered only current and backup root references, so later saves could
retire a version needed by queued model metadata or region work.

## Automatic request lifetime

An accepted block/model request with a 32-byte checkpoint acquires an in-memory
reference keyed by asset and checkpoint. The empty asset namespace denotes blocks.
The reference covers pending, active and unread completed work, and is released
when its result is polled. Failed requests follow the same release accounting.
Requests without a checkpoint retain their existing active-version semantics;
they do not reserve a historical catalog.

Cleanup keeps the union of current/backup root pins and read/lease references.
A short queue-lock section snapshots references and marks the retention sweep
active. While disk validation and pin removal run, new checkpoint-bearing requests
and lease acquisitions return 0/backpressure. They never wait for the store I/O
mutex or perform disk I/O. The queue mutex is not held across disk operations.
Existing requests can complete, results can be polled and leases can be released
during the sweep; its conservative snapshot may retain a pin until the next save.
A scope guard clears the sweep flag on success and failure.

This protects checkpoints that still exist when retention is established. It
cannot resurrect a previously retired version; such reads fail explicitly. No
request substitutes newer data for a missing exact version.

## Explicit scene/pager lifetime

`configure_checkpoint_retention(lease_limit)` sets a bounded handle budget from
1 to 4,096, default 1,024. The default accommodates the 256-asset schema with
multiple overlapping generations plus blocks. Tightening below the number of
active leases fails without revoking holders. Request-count and payload-byte
limits remain independent and unchanged.

`retain_read_checkpoint(asset, checkpoint)` returns a positive lease handle or 0
for invalid arguments, closed storage, exhausted budget or a retention sweep in
progress. Use an empty asset for blocks; model assets must be registered. Handles
increase across stop/start and release/reacquire cycles of the archive object.
Duplicate holders get different handles and independent references.

Retention is a reservation, not disk existence/integrity validation. The intended
sequence is:

1. Obtain the checkpoint identity from the selected world version.
2. Retain it before submitting metadata/region reads; retry later on backpressure.
3. Verify successful exact read results before installing scene metadata.
4. Keep the lease while pending work or unavailable scene records need that
   historical version. Handover to a successor must establish and verify its
   retention before releasing the previous lease.
5. Call `release_read_checkpoint(handle)` when the version is no longer needed.
   Duplicate/stale releases return false and cannot affect another holder.

Acquire the explicit lease before polling away the last automatic reference;
otherwise cleanup can run in the handover gap. A failed existence check requires
releasing the lease and selecting/reloading an authoritative world version.

`release()` drains readers and closes storage, invalidating all in-memory leases.
Unread result payloads remain consumable as before, but their disk-retention
protection ends. Unread completions still prevent archive reuse until polled.
The coordinator must finish/cancel scene work before closing its archive; leases
are not durable across object destruction, process exit or another writer's session.
Lifecycle calls retain the existing single-owner, no-racing-acquire/release rule.

## Bounds and collection

The reference table contains at most the configured explicit-handle budget plus
64 outstanding requests, with duplicate keys merged. Lease handles retain only
asset/checkpoint identities, not additional region packet copies or worker threads.
The store's separate limit of 16 durable checkpoints per catalog still applies.
Holding too many historical generations can therefore make a new save fail at
that limit; callers must release obsolete generations rather than silently evict
needed data. Pin/blob collection stays on the existing publication path. Polling
and lease release never perform file deletion, so cleanup may wait until a later
save.

`region_read_stats()` reports `checkpoint_leases`, `checkpoint_lease_limit`,
`retained_checkpoint_keys`, `checkpoint_sweep_active` and cumulative
`checkpoint_busy_rejections`. These measure in-memory retention, not proof that
an arbitrary reserved checkpoint exists on disk.

## Validation

The short `region_checkpoint_retention` fixture covers old block/model/metadata
reads across root rotations, explicit and duplicate holders, bounded configurable
capacity, stale/absent checkpoint failures, 64 reads concurrent with 16 saves,
cleanup failure/recovery and release/reacquire lifetime. It records the number
of requests that encountered retention-sweep backpressure.

Run from the repository root:

```text
python TerraForest/tools/test_native_release.py --godot <engine.exe> --addon structures --test region_checkpoint_retention
```

Evidence: [reports and exact build hashes](evidence/region_checkpoint_retention/).
This is storage correctness/lifetime validation, not a frame-time or sustained
thermal test. Automatic model paging remains unconnected: shared scheduling,
scene handover, dirty-save preparation and transfer/renderer timing gates remain.
No file format or licensing changes were introduced; the added implementation is
project-owned 0BSD C++ using the existing pinned prebuilt godot-cpp toolchain.

Final debug and release each pass 29 retention checks. The concurrent workload
encountered 14 debug / 12 release sweep-busy rejections, retried them, and completed
all 64 reads correctly. Existing release regressions pass 71 shared-reader checks
and 82 compound archive/save checks. The native transfer timing gates retain their
previous unresolved results; this storage change does not qualify automatic paging.
