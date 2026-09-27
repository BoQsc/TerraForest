"""Preserve typed terrain bridge parity, concurrency and integration evidence."""
from pathlib import Path
import hashlib
import json
import shutil

root=Path(__file__).resolve().parents[1]
reports=root/'reports'
evidence=root/'docs/evidence/terrain_native'
evidence.mkdir(parents=True,exist_ok=True)
bridge=json.loads((reports/'terrain_bridge.json').read_text())
assert bridge['byte_parity'] and all(r['failures']==0 for r in bridge['variants'].values())
for name in ['world_persistence','world_persistence_release','water','integration','water_integration']:
    report=json.loads((reports/(name+'.json')).read_text())
    assert report['failures']==0
scene=json.loads((reports/'water_integration.json').read_text())
assert scene['presentation']['fair_graphical_sample']
assert all(r['pass'] for r in json.loads((reports/'isolation.json').read_text()))
for name in ['terrain_bridge.json','terrain_bridge_legacy.log','terrain_bridge_template_debug.log',
             'terrain_bridge_template_release.log','world_persistence.json','world_persistence_release.json',
             'water.json','integration.json','water_integration.json','water_integration_gpu.log',
             'water_lake.png','isolation.json','pack_smoke.log',
             'volumetric_terrain_build_template_debug.json','volumetric_terrain_build_template_release.json']:
    shutil.copy2(reports/name,evidence/name)
files=['addons/volumetric_terrain/native/'+name for name in ['core.cpp','core.h','platform.h','terrain_binding.cpp']]
files+=['tests/terrain_native.gd','tools/test_terrain_bridge.py']
for target in ['template_debug','template_release']:
    name='addons/volumetric_terrain/bin/'+('terrain_core.windows.x86_64.dll' if target=='template_debug' else 'terrain_core.windows.template_release.x86_64.dll')
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==bridge['variants'][target]['library_sha256']
    files.append(name)
(evidence/'tested_files.sha256.json').write_text(json.dumps({name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in files},indent=2)+'\n')
(root/'docs/TERRAIN_NATIVE_VALIDATION.md').write_text('''# Typed terrain binding and independent native worlds

Windows terrain now builds with pinned Zig and prebuilt godot-cpp. The existing
native generator, mesher and packet/save formats are retained. The typed bridge
replaces manual Variant/ABI plumbing. It owns a cancellation counter outside its
World state so reset/load cannot replace that counter. Native mutations and queries
serialize on each instance's mutex; cancellation and its query bypass that mutex.
Allocation-error flags are thread-local. No godot-cpp sources were rebuilt.

## Evidence

- 25 native checks pass in each clean debug/release test project.
- Seven legacy checks establish six field/snapshot/mesh SHA-256 fingerprints.
  Both new variants match those fingerprints exactly. The baseline DLL is read
  from published commit e1181687e14e2dac03598af2e35044d47917e721.
- Two simultaneous cold native mesh jobs are observed inside their native calls.
  Cancelling one aborts that job while its neighbor completes. The neighbor's
  complete render/collision packet matches a fresh sequential world byte for byte.
- 200 concurrent same-world block edits preserve all blocks and revisions; their
  render/collision output matches a sequential build.
- 1,000 native resets lose none of 1,000 concurrent cancellation increments.
- 31 terrain/forest integration checks, 45 water checks and all three addon
  isolation checks pass with the rebuilt terrain DLL.
- 43 compound-save checks pass in both debug and clean release configurations.
  The release test now loads release terrain, runtime and water libraries.
- 13 real-scene checks pass at 1920 x 1080 fullscreen, 100% render scale. The
  [inspected screenshot](evidence/terrain_native/water_lake.png) retains the forest,
  excavated lake and expected voxel shoreline. No frame-rate speedup is claimed.
- The exported PCK starts with six external native libraries (debug/release
  variants of terrain, runtime and water).

## Scope and remaining limits

This proves native isolation for these operations and fixtures, not multiplayer
readiness. The public TerrainWorld facade still enforces one active scene world
per process until cache paths and save-slot ownership support multiple scenes.
The historical Linux DLL has not been rebuilt or migrated. The raw standalone
core retains a global cancellation fallback for legacy tools without an owner.
Each caller must keep its native object alive until its operation finishes.

The fixed world dimensions, inherited native containers and their allocation-failure
limitations remain; this work is not an allocator fault-injection certification.
Networking, region ownership, primitive prefab editing, revised generation,
native scheduling and long-run capacity tests remain outstanding.

## Reproduce

From the project directory, after stopping processes that use its DLLs:

```text
python tools/build_native.py --addon volumetric_terrain --target all
python tools/validate.py --test terrain_native
python tools/test_terrain_bridge.py
python tools/validate.py --test integration
python tools/validate.py --test world_persistence
python tools/test_native_release.py --test world_persistence
python tools/validate.py --test water
python tools/test_isolation.py
python tools/validate.py --test water_integration --gpu
python tools/export_pack.py
python tools/record_terrain_native_validation.py
```

The legacy comparison requires Git history or `--legacy-dll PATH` to a retained
baseline DLL. Other tests work directly from the source archive. Raw results,
build metadata and tested file hashes are in `docs/evidence/terrain_native`.
''',encoding='utf-8')
print('Recorded native terrain isolation and compatibility evidence.')
