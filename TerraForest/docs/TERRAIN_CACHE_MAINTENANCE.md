# Offline terrain cache maintenance

The current terrain worker admits derived meshes up to 512 MiB based on an
instance-local startup inventory. It does not evict old snapshots. Once full,
the cache stops accepting new meshes; terrain generation continues normally.
Concurrent processes do not share a quota transaction. This remains a runtime
architecture limitation, not a hard cross-process disk guarantee.

`tools/maintain_terrain_cache.py` provides offline cleanup of these rebuildable
meshes. It defaults to a read-only inventory and a 384 MiB retention budget:

```text
python tools/maintain_terrain_cache.py "PATH/TO/terrain_cache" --budget-mib 384
```

On Windows the demo normally uses
`%APPDATA%/Godot/app_userdata/TerraForest/terrain_cache`. Pass the expanded path
in PowerShell, which does not expand `%APPDATA%` syntax.

Stop every editor, game, server and bake process using that directory before
applying the plan:

```text
python tools/maintain_terrain_cache.py "PATH/TO/terrain_cache" --budget-mib 384 --apply --offline
```

`--offline` is the operator's assertion, not process detection or an acquired
runtime lock. Maintenance must not run concurrently with writers or directory
replacement. A future native cache owner must coordinate reads, writes, eviction,
reservations and cross-process ownership.

The tool enumerates only the expected signature/snapshot/tile hierarchy. It
checks the TRC header, mesh version and signed tile coordinates, then selects
oldest-written packets until recognized bytes fit the requested quota. Reads do
not refresh age, so this is FIFO by write time, not LRU. Enumeration is capped at
100,000 entries by default; exceeding the limit aborts before deleting anything.
The scan reads only 76 header bytes per candidate. Application streams SHA-256
in 64 KiB buffers and rechecks file identity before unlinking each packet.

Links, junctions, unknown namespaces, non-packets, temporary files and canonical
world saves are retained. Empty directories are also retained. Corrupt digests,
changed files and failed deletions leave entries in place and cause a nonzero
apply result if the plan could not be fulfilled. The budget covers recognized
TRC packets only, not every byte in the directory or disk free-space reserves.

Validation on 2026-09-28:

- All nine disposable-fixture tests passed with `python tools/test_terrain_cache_maintenance.py`.
- Tests cover age ordering across snapshots, dry-run behavior, offline assertion,
  valid deletion, canonical/unknown file preservation, corrupt hashes, changed
  files, invalid headers/keys/lengths/namespaces, outside-root entries, scan caps,
  and symlink rejection (executed successfully on this Windows host).
- Live read-only inventory: 2,973 recognized files, 536,839,356 bytes. A 384 MiB
  budget selected 956 files / 134,352,568 bytes. No live entries were deleted.
- Resource path/addon boundary audit passed. No runtime code or DLL changed;
  this milestone makes no new rendering, native performance or endurance claim.
