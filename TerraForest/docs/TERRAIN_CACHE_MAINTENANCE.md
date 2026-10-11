# Offline terrain cache maintenance

The terrain worker now uses a native exclusive Windows cache lease and a bounded
recency index. The default logical file-byte quota remains 512 MiB. After complete
accounting, a full cache schedules one checked packet eviction per idle worker
call, freeing at least the requested space or one eighth of the budget. Mesh
requests never synchronously delete a batch of files. Uncached meshes still
render; a packet rejected for space can be cached on a later request. Lake
payloads have a bounded deferred queue (16 entries / 16 MiB).

The native index holds at most 65,536 recognized terrain/lake packets. Initial
ordering uses file write time; successful reads update in-memory recency only.
Recency is not persisted. Deletion rechecks file identity, size and timestamp,
then deletes by the opened handle. A competing updated process remains read-only.
A temporary reader conflict defers eviction until a later space request without
invalidating accounting or spinning in idle maintenance; pending lake cache
copies may be dropped in that case, leaving their live volumes unaffected.
External candidate changes invalidate accounting and stop writes/eviction until
reconfiguration. Root/ancestor reparse points and directory junctions are rejected.

Canonical saves, unknown files and temporary files are not eviction candidates.
Unknown/hidden file bytes count toward the quota; an unknown-only full directory
therefore remains read-only. Accounting is capped at 262,144 visited entries and
32 directory levels. Empty directories are retained. The quota is for logical
file bytes, not filesystem metadata, a disk-free reserve or a hard I/O deadline.
It coordinates updated cache owners only: old builds, offline tools and external
file writers do not participate in the lease. Canonical world data stays separate.
See `docs/evidence/cache_eviction` for scoped validation and the retained world-test
path mistake; sustained travel/mining and disk-pressure qualification remain open.

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
replacement. The runtime owner coordinates updated game instances, but this offline tool does not
acquire its lease. Keep the offline requirement; do not run cleanup beside a game.

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
