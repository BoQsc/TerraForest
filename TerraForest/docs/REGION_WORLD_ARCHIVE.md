# World saves backed by building-region checkpoints

Real process-interruption validation now passes three debug and three clean-release
trials, including fresh-process checkpoint reconstruction and subsequent saves.
See [interruption evidence and scope](REGION_SAVE_INTERRUPTION.md).

The main world now uses `NativeRegionWorldArchive`, a C++ adapter around
`NativeWorldArchive` and the registered `NativeStructuresSnapshot` schema. The
terrain backend still owns save/load sequencing and component generations. Region
conversion, checkpoint publication, archive conversion and reconstruction execute
on that save worker. Scene capture and restore remain on the scene thread.

## Files and publication order

For `world.trw`, the adapter exclusively manages the sibling directory
`world.trw.regions`. The world root retains terrain, water, model records and unknown
addon sections; its structures section references a pinned block-region checkpoint.
Back up or move **the root, its `.bak`, and the entire `.regions` directory together**.
A root file alone is no longer a self-contained world.

Saving validates the complete resident structures bundle, splits block chunks into
64-cell regions, reuses matching immutable blobs, publishes a catalog, pins it,
then publishes the root archive last. Full-snapshot replacement removes active
catalog regions absent from the newer snapshot. Unchanged block data reuses its
catalog/checkpoint while model or terrain changes may still publish a new root.
No per-cell nodes or GDScript serialization loops are introduced.

Before creating another pin, and after successful root publication, the adapter
reads and validates the actual current and backup roots. It releases only pins
not referenced by those roots. This also retires abandoned pins from unsuccessful
saves. A failed root replacement leaves the existing root readable; backup rotation
may already have happened, so cleanup always uses the files actually present.
Cleanup after a successful publication is best effort and cannot turn that success
into a reported failed commit. Up to 32 blob entries are inspected afterward.

The sibling directory belongs exclusively to this adapter. Do not place independent
checkpoint pins or external save references there: retention tracks only this
root and its one backup. Archival copies need their own complete directory copy.
Corrupt/unresolved root or backup metadata prevents retention reconciliation and
further saves; it is not silently discarded. Existing store and root leases prevent
cooperative concurrent writers. This does not certify arbitrary external mutation,
physical power loss or network-filesystem behavior.

## Loading, schema and compatibility

The new `TFSR` v1 structures section has the same bounded envelope as `TFSB` v1,
but contains a 32-byte checkpoint identity in place of resident block bytes. Its
model snapshots retain their asset IDs and transforms; the section has its own
SHA-256. Ordinary structure validators deliberately reject reference bundles.

The adapter validates the reference, reads and validates every referenced region,
then reconstructs a normal TFSB bundle before the terrain backend validates and
applies component state. Unknown model assets fail before scene restoration.
Newly registered assets absent from an older save still restore empty. Old TFSB
roots load normally and migrate on the next successful save; the old root remains
the backup. Legacy terrain-only loading remains handled by the terrain backend.
Older applications cannot load checkpoint-reference roots without this adapter.

`NativeBlockRegionStore.publish_block_snapshot(bytes)` performs complete-index
replacement from a valid TFBL snapshot. `read_block_checkpoint(id)` reconstructs
its canonical TFBL bytes. These synchronous methods are for a save-worker owner,
not concurrent authoring or gameplay-frame use. The adapter's `configure(archive,
structures_codec)` is one-shot. It implements `acquire`, `release`, `encode`,
`decode`, `read` and `publish` for the existing terrain persistence interface.
Acquire/release happen at lifecycle boundaries; initial directory/catalog opening
can block during startup. Other operations must not race that lifecycle.

Applications opt in after registering the structures provider and before attachment:

```gdscript
persistence.register_component("structures", structures.capture_snapshot,
    structures.restore_snapshot, structures.snapshot_validator(), structures.empty_snapshot())
persistence.enable_region_structures()
persistence.attach(terrain)
```

The main demo selects this path. Other consumers keep the original whole-file
archive unless they opt in. Temporary graphical tests skip disk saves as before.

## Current bounds and validation

This step integrates region-addressed disk storage, not automatic runtime paging.
Capture still serializes all resident authored blocks and models. Reload reconstructs
all blocks, capped at 2,048 chunks; a larger checkpoint fails instead of truncating
it. Whole-world capture still rejects explicitly unloaded regions. The existing
64 MiB structures and 256 MiB root limits remain. The conversion uses transient
chunk maps and packed buffers; peak memory and large-world latency are unmeasured.
Model regions, delta capture, predictive streaming and background admission remain
unfinished.

The native adapter suite passes 35 checks in debug and clean release. It covers exact
conversion, signed coordinates, empty/replacement snapshots, model binding, repeated
saves beyond checkpoint capacity, current/backup reconstruction and a real root
replacement failure. The integrated terrain/water/structures suite passes 66 checks
in debug and clean release, including generation ordering, shutdown during reload,
model IDs, registry extension and corrupt/unknown-asset rejection. The temporary
main-world graphical suite passes 167 checks at 1920×1080 fullscreen.

An initial integrated debug run failed to become ready and subsequently timed out
after a dependent assertion accessed missing data. The cause is unconfirmed;
subsequent debug and clean release runs passed. The test now uses a unique slot and
stops after failed initial readiness with startup diagnostics rather than attempting
dependent saves. These successes do not establish long-run reliability. Evidence
is retained in `docs/evidence/region_world_archive`.
