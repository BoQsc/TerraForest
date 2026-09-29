# Compound world snapshots

The main world now publishes block-region checkpoint references through a native
archive adapter, retaining current and backup roots. See [region-backed world saves](REGION_WORLD_ARCHIVE.md).
Full-resident capture/restore limits remain; automatic runtime paging is unfinished.

Terrain, lake definitions, building blocks and registered static-model placements share one versioned canonical snapshot in the terrain demo. The demo attaches `world_runtime/world_persistence.gd` before terrain startup and registers the water catalog and structures bundle as addon sections. Native C++ performs archive packing, hashing, schema validation, bounded file reads and Windows publication on the terrain worker. Small GDScript callbacks collect/restore addon configuration and connect scene ownership; a dirty structures bundle is serialized on capture before worker publication.

## Format and ownership

The existing `user://worlds/<slot>.trw` path is retained. New files begin with `TFWORLD1`; the original terrain payload is an opaque `terrain` section. The archive has a 48-byte header: eight-byte magic, little-endian uint32 schema and section count, then a 32-byte SHA-256 digest covering the schema/count and complete section body. Each section contains uint32 ASCII-name length, uint32 byte length, name and payload. Names are sorted, unique, lowercase ASCII letters/digits/underscore, at most 48 bytes. The terrain section is mandatory. Trailing bytes, duplicate/noncanonical names, unsupported versions, length violations and digest mismatches are rejected.

The hard limit is 256 MiB per archive, 64 sections, and 64 MiB per non-terrain section. The component ceiling was raised from 16 MiB to accommodate the existing block snapshot's worst-case RLE size plus static placements. Earlier native runtime versions reject sections above their former ceiling; use the updated archive DLL with this integration. Hashing and publication read-back use 64 KiB chunks rather than another whole-file hash buffer. Encoding/decoding still materializes the snapshot and its component payloads. This is a bounded single-world snapshot bridge, not yet the requested scalable region/delta database.

Water's version-1 catalog uses a 20-byte header (magic, schema, count, uint64 next ID) and 56 bytes per lake. Records store a stable ID, origin, cell dimensions, spacing, fill level, seed and reserved zero field. At most 16 definitions are stored. Native validation rejects invalid sizes, nonfinite values, duplicate IDs and unsupported fields. The allocation cursor survives deletion and restart, so IDs are not reused merely because the catalog becomes empty. Derived occupancy and surface meshes are rebuilt against the loaded terrain.

## Consistent saves and shutdown

The worker owns canonical terrain and addon bytes. Main-thread captures carry a monotonically increasing generation and the epoch of the last completed restore. Each accepted edit carries its component snapshot. Older queued saves cannot replace newer component state; captures from a pre-load epoch cannot overwrite a newly loaded world. Unknown addon sections remain opaque and survive save/load when their addon is disabled.

An invalid live component capture prevents publication without poisoning the disk-read state. A later valid capture can resume saving. Even a rejected capture advances the generation watermark so an older queued capture cannot overtake it. This recovery does not bypass protection after a corrupt file is loaded: failed disk validation still disables writes until an explicit recovery/reset. Structures capture caches serialized bytes until a native edit signal; returned byte arrays and restored cache entries are defensively duplicated so callers cannot mutate the cache.

Orderly shutdown drains accepted queued edit commands before saving, while skipping their now-unnecessary render work. It also handles a queued load/reset. Old derived mesh packets are discarded when drained mutations change the canonical world. Reload callbacks validate known component schemas before terrain load; scene restoration failure prevents world readiness and disables saving for the session.

Native terrain revision and render publication counter are separate values. Water sampling checks the native revision, including after saved-world reload; scene publication still checks the render counter and epoch.

## Publication and recovery

`NativeWorldArchive.acquire(absolute_path)` takes an exclusive Windows handle on `<path>.lock`, preventing cooperative concurrent writers in other processes. The handle lives until shutdown or process termination. The marker file can remain; an unlocked marker does not mean the world is in use.

Publication validates the archive, writes a uniquely named temporary file with write-through, flushes it, checks the complete read-back, and copies the previous canonical snapshot to a separately published `.bak`. The canonical path is replaced using same-directory `MoveFileExW` with replace/write-through flags; it is never first moved out of the way. A rejected write leaves the previous canonical file intact. Orphan `.pending.*` files from a killed process are not adopted as committed saves. Automatic orphan cleanup is not yet implemented.

Legacy raw terrain snapshots load through the original native decoder. The first successful compound save migrates the canonical file while retaining the exact old file as `.bak`. A malformed container, malformed known addon payload or rejected terrain payload prevents startup and saving, preserving the input file. Recovery from `.bak` is explicit; the engine does not silently replace a corrupt canonical file with older data.

## Provider API

Before `terrain.start(...)`, instantiate `world_persistence.gd`, register providers, then attach it to the terrain facade:

```gdscript
water.prepare()
persistence.register_component("volumetric_water", water.capture_snapshot,
    water.restore_snapshot, water.snapshot_validator(), water.empty_snapshot())
persistence.attach(terrain)
```

Capture returns fresh immutable `PackedByteArray` data. Restore returns `bool`. A provider validator is a stateless native RefCounted object with `validate_snapshot(bytes)`; it can run on the terrain worker while other immutable validation occurs. Providers are registered only before attachment. The terrain addon remains usable by itself with its legacy format; reading compound snapshots requires the runtime archive adapter.

`structures/structures_world.gd` owns one native block world and up to 256 registered model collections. Its native `NativeStructuresSnapshot` validator freezes the asset-key registry and validates every nested block/model snapshot before terrain is applied. All model collections occupy one `structures` section, rather than one world section per mesh asset. Added assets restore empty when absent from an older bundle; an unknown saved asset rejects loading to avoid silently losing objects. Model identities are locked when registered. See [structures persistence validation](STRUCTURE_PERSISTENCE_VALIDATION.md).

## Evidence and remaining work

`tests/world_archive.gd` covers archive/catalog validation, bounded schemas, stable ID cursors, publication, competing handles and backup integrity. `tests/world_persistence.gd` uses real terrain and water across new world instances, including legacy migration, unknown-section preservation, corrupt addon protection, immediate shutdown after edits, and shutdown while a reload is queued. Both suites also run against release DLLs in a clean project.

`tools/test_archive_process.py` starts separate Godot writer/probe processes, observes an in-progress temporary file, force-kills the writer, and checks that a new process can acquire the lease and validate canonical/backup files. These are process-termination tests, not physical power-loss or disk-failure certification.

Region-addressed storage, edit journals/compaction, cross-region transactions, water bake caches, server authority and network replication remain required work. There is no multiplayer capacity claim attached to this snapshot format.
