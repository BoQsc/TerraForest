# Saving while building regions are unloaded

The main world's region-backed save provider now captures resident block cells
and references to unloaded regions together. Saving a resident edit or closing
the world preserves the unloaded cells in the new checkpoint. Deleting the last
resident cell in a region removes that region from the next checkpoint.

`structures_world.capture_storage_snapshot()` returns ordinary TFSB bytes while
all regions are resident. Otherwise it uses the native TFSP version 1 envelope:
the existing structures header/model records/checksum, with a block payload of
resident-byte length, unavailable-region count, resident TFBL bytes, and sorted
44-byte xyz/digest records. Both counts are little-endian unsigned 32-bit values;
coordinates are signed 32-bit values. The 64 MiB structures limit still applies.
Capture caches are separate from the complete-world cache and invalidate on
block or model changes. Returned packed arrays use isolated copy-on-write data.

The native codec checks nested block/model formats, registered asset identities,
lengths, checksums, region bounds, sorting, uniqueness, and disjointness from
resident regions. At most 65,536 combined regions are accepted. Storage validation
does not read disk or establish that the unavailable versions are committed.
The store performs that exact digest check against its active catalog at publish.
An unloaded empty region also needs a committed catalog entry.

Only the region-enabled persistence coordinator selects the adapter's storage-aware
validator. `NativeStructuresSnapshot.validate_snapshot`, its ordinary `decode`,
the scene's `restore_snapshot`, and whole-world `capture_snapshot` retain their
complete-residency contract. A partial envelope cannot be mistaken for a complete
scene or accepted as a published world root. Legacy persistence stays unchanged.

The archive publishes resident regions plus verified unavailable references,
pins the resulting catalog, and publishes the root last as an ordinary TFSR
checkpoint reference. TFSP is a transient save request, not a new on-disk world
format. Terrain, water, and static model records remain in the same compound
publication. Current and backup roots retain their corresponding checkpoints.
Malformed envelopes and stale/absent references cannot replace the canonical root.
Existing root replacement failure and process-interruption limits still apply;
this does not claim power-loss durability or concurrent multiplayer merging.

Use `capture_storage_snapshot` when registering a structures component with
`enable_region_structures()`. Register the ordinary immutable structures codec;
the coordinator selects the native adapter validator before the worker starts.
All byte encoding, semantic validation and region publication are native C++.
GDScript connects scene providers and schedules capture only.

## Remaining scope

Automatic runtime paging is not enabled. The main demo still reconstructs the entire
checkpoint, with the current 2,048-chunk bound. An opt-in metadata-first path now
exists (see METADATA_WORLD_LOADING.md); bounded automatic region admission remains
necessary before enabling it for interactive large-world use.
Capture still serializes every resident block and static model. Dirty-region
delta saves, model-region storage, measured peak memory, large-world latency,
predictive vehicle streaming and multi-hour endurance remain unfinished.

Tests cover native malformed envelopes with recomputed outer checksums, stale
references, exact reconstruction, backups, demolition and reopening. The real
terrain worker test saves and shuts down with an unloaded persisted region,
preserves model identities, exercises both capture caches, and rejects partial
data through legacy APIs. Evidence is retained in `docs/evidence/partial_world_archive`.
