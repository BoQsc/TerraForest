# Native static-model region transfers

`NativeStaticBatch` supports checked transfers of one 32-metre origin group.
`capture_region(Vector3i)` uses the existing spatial membership index, so it
visits that group's placements rather than scanning every placement. The TFMR
version-1 packet contains the signed region coordinates, asset-bound TFSI
records and a SHA-256 checksum. Negative coordinates use floor division.
Every record must belong to the packet's origin group. A group can contain up
to the collection's existing 100,000-placement limit; transfer work is not
time-sliced, so a dense group is still a large synchronous operation.

## Transfer contract

1. Capture a loaded region. Store the packet externally and verify the write
   before releasing the resident records. The native transfer API does no I/O.
2. Call `unload_region(packet)`. It compares the complete current region with
   the supplied capture. A newer edit, malformed packet, wrong asset or already
   unloaded region is rejected without mutation.
3. Unload releases placement transforms, spatial memberships, draw buffers and
   collision proxies. It retains a checksum, conservative local bounds, count
   and reserved IDs. These reservations prevent another region taking the IDs.
4. `restore_region(packet)` accepts only the exact packet for a currently
   unloaded region. It restores stable IDs and records, invalidates derived
   rendering/collision state and releases the reservations. It cannot import
   arbitrary packets into resident regions or overwrite newer resident edits.

Both operations run on the collection's scene owner thread. Observers receive
one `changed` notification after the complete state transition. They form an
external-change barrier for `NativeStaticHistory`; history is not preserved
across transfers. Automatic paging will need history-aware admission before
using this path during ordinary editing.

## Correctness while records are unavailable

- Whole `capture_snapshot()` returns empty bytes, so the existing compound
  snapshot encoder rejects an incomplete save instead of publishing data loss.
- `capture_region()` also refuses an unloaded region. `is_region_loaded()`
  distinguishes unavailable data from a loaded empty origin group.
- Insert/upsert into an unloaded origin group is rejected. IDs from unloaded
  records cannot be reused, and both placement/group limits count unloaded data.
- Legacy `set_instances()` rejects partial collections. Explicit validated
  whole `restore_snapshot()` replaces all state, including reservations; this
  remains the intentional whole-world replacement operation.
- Asset replacement and collision-prototype reconfiguration are rejected while
  regions are unloaded because the retained bounds describe the current asset.
- Collision readiness is false wherever unloaded proxy bounds intersect the
  query, including shapes extending beyond their 32-metre origin group.
  Intentionally non-colliding decorative assets keep their existing semantics.
- Vegetation queries conservatively exclude retained group bounds. They may
  exclude gaps within a group until exact records return, rather than regrowing
  through missing structures. This is not exact exclusion without residency.

`region_stats()` separates resident transforms, logical instances and ID
reservations. Byte counters measure payload only, not allocator/node overhead,
process memory, temporary packet copies, or the caller's disk cache. Retaining
one tree-set entry per unloaded ID is still O(logical instance count). This is
not yet an arbitrary-scale compact persistent identity index.

## Integration boundary

Automatic main-world model paging is deliberately not enabled. The native
transfer and save/readiness guards are prerequisites for it, not a persistent
catalog. Asset-aware disk catalog/checkpoints are now available through
[NativeModelRegionStore](MODEL_REGION_CATALOG.md). Still required: metadata-only
bootstrap, partial compound saving, bounded I/O queue, history-aware eviction,
and distance/visibility policy that preserves the requested distant world
representation. Until these are connected, the main world retains its previous
fully resident authored-model storage and bounded derived render/collision sets.

Focused test: `tests/static_model_regions.gd`. It exercises stale/corrupt packets,
negative regions, reserved-ID allocation, unavailable collision/exclusion,
snapshot/history guards and a 100,000-record disk round trip. Results are recorded
in `docs/evidence/static_model_regions`: 36 transfer checks pass with both debug
and release DLLs, including immediate derived-state release and subsequent
render/collision readmission. The release test runs in an isolated temporary
project. Existing static placements pass 235 checks; region-backed compound
persistence passes 76 checks. All are headless correctness tests on the new host.

The pressure fixture writes and verifies 99 packets of 56,125 bytes each, leaving
1,000 of 100,000 transforms resident. Resident transform payload changes from
4,800,000 to 48,000 bytes; unloaded ID payload is 792,000 bytes plus tree-node
overhead. Restoring the disk packets reproduces the complete original snapshot
byte for byte. The serial capture/write/unload loop takes several seconds;
this synchronous API is not yet qualified for per-frame use. No new FPS,
total-process memory or distant-rendering claim follows from this test.
