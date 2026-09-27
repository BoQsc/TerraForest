# Compound storage validation — 2026-09-27

Current Windows/Godot build, using Zig and the pinned prebuilt godot-cpp libraries.

| Suite | Result |
| --- | --- |
| world_archive | 23 passing checks |
| world_archive_release | 23 passing checks |
| world_persistence | 43 passing checks |
| world_persistence_release | 43 passing checks |
| integration | 31 passing checks |
| persistence | 14 passing checks |
| water_integration | 13 passing checks |
| Independent writer/probe/recovery processes | 3 passing forced-termination trials |

Archive/catalog tests cover deterministic bytes, required and opaque sections, schema/bounds/type validation,
checksum corruption, stable lake ID cursors, competing handles, verified publication and exact prior backups.
The integrated tests use actual terrain edits and lake volumes, new world instances, legacy migration,
unknown addon preservation, corrupt addon protection, shutdown with an accepted edit, shutdown with a queued reload,
and deletion/restart without persistent ID reuse. The expected corrupt-snapshot diagnostic is part of the passing protection test.

Release tests copy the relevant addons into a clean temporary project and route both extension feature entries to release DLLs.
The independent process tests observe an in-progress temporary snapshot, kill the live writer without graceful cleanup,
and verify both canonical/backup integrity and lease reacquisition in another process. They do not simulate physical power loss.

The complete water/terrain/forest scene also passes its graphical checks at 1920×1080 exclusive fullscreen,
100% render scale. The screenshot in evidence/storage/water_lake.png is a real renderer capture.
The resource pack starts with all five required external Windows DLLs.

No broad production-readiness or multiplayer claim follows from these tests. World snapshots remain bounded to 256 MiB;
region/delta storage, journal/compaction, water bake caching, networking and the rest of DELIVERY_STATUS.md remain outstanding.
See WORLD_STORAGE.md for the exact format, ownership rules, compatibility and recovery limitations.
