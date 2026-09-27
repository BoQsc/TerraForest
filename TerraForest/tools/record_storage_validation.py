"""Collect current compound-snapshot and process recovery evidence."""
from pathlib import Path
import json
import shutil
root=Path(__file__).resolve().parents[1]
reports=root/'reports'
evidence=root/'docs/evidence/storage'
evidence.mkdir(parents=True,exist_ok=True)
names=['world_archive','world_archive_release','world_persistence','world_persistence_release','archive_process','integration','persistence','water_integration']
data={name:json.loads((reports/(name+'.json')).read_text()) for name in names}
assert all(r['failures']==0 for r in data.values())
assert data['water_integration']['presentation']['fair_graphical_sample']
for name in names:
    shutil.copy2(reports/(name+'.json'),evidence/(name+'.json'))
    log=reports/(name+'.log')
    if log.exists():shutil.copy2(log,evidence/log.name)
for name in ['water_integration_gpu.log','water_lake.png','pack_smoke.log']:
    shutil.copy2(reports/name,evidence/name)
rows='\n'.join(f'| {name} | {len(data[name]["checks"])} passing checks |' for name in names if 'checks' in data[name])
text=f'''# Compound storage validation — 2026-09-27

Current Windows/Godot build, using Zig and the pinned prebuilt godot-cpp libraries.

| Suite | Result |
| --- | --- |
{rows}
| Independent writer/probe/recovery processes | {len(data['archive_process']['trials'])} passing forced-termination trials |

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
'''
(root/'docs/STORAGE_VALIDATION.md').write_text(text,encoding='utf-8')
print('Recorded compound storage and recovery evidence.')
