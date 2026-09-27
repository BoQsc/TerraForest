"""Record native rectangle-merge validation without replacing historical evidence."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parents[1]
reports = root / 'reports'
destination = root / 'docs/evidence/water_mesh'
destination.mkdir(parents=True, exist_ok=True)
native, release, scene = [json.loads((reports / name).read_text()) for name in
                          ['water.json', 'water_release.json', 'water_integration.json']]
assert all(r['failures'] == 0 and all(c['pass'] for c in r['checks']) for r in [native, release, scene])
assert scene['presentation']['fair_graphical_sample']
assert any('62 strips to one quad' in c['name'] for c in native['checks'])
for name in ['water.json', 'water.log', 'water_release.json', 'water_release.log',
             'water_integration.json', 'water_integration_gpu.log', 'water_lake.png',
             'volumetric_water_build_template_debug.json', 'volumetric_water_build_template_release.json']:
    shutil.copy2(reports / name, destination / name)
files = ['addons/volumetric_water/native/lake_volume.cpp', 'tests/water.gd']
for target in ['template_debug', 'template_release']:
    name = f'addons/volumetric_water/bin/volumetric_water.windows.{target}.x86_64.dll'
    build = json.loads((reports / f'volumetric_water_build_{target}.json').read_text())
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == build['sha256']
    files.append(name)
(destination / 'tested_files.sha256.json').write_text(json.dumps({
    name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in files
}, indent=2) + '\n')
(root / 'docs/WATER_MESH_VALIDATION.md').write_text(f'''# Native water surface rectangle merging

The water mesher merges adjacent occupied surface cells across both X and Z.
It preserves the voxel shoreline, central islands and uncovered cave roofs.
The native operation uses a fixed 16 KiB local mask and does not modify the
published water occupancy. It runs when a surface is extracted, not every frame.

## Verified geometry reduction

| Sealed rectangular basin | Previous row strips | Current rectangles | Triangle count |
| --- | --- | --- | --- |
| 8 x 6 x 8 cells | 6 | 1 | 12 to 2 |
| 64 x 64 x 64 cells (maximum cell budget) | 62 | 1 | 124 to 2 |

Previous counts follow the prior one-strip-per-occupied-row algorithm.
Current counts are asserted by native API tests. This is a geometry reduction,
not a matched frame-rate benchmark; irregular lakes need multiple rectangles.
Greedy merging does not promise the globally smallest rectangle partition.

## Validation

- Native debug: {len(native['checks'])} checks passed.
- Native release in a clean Godot project: {len(release['checks'])} checks passed.
- Real terrain/vegetation scene: {len(scene['checks'])} checks passed at 1920 x 1080 fullscreen, 100% render scale.
- Zig compiled the changed extension source against the pinned prebuilt godot-cpp library for both variants.

The coverage oracle checks every grid-cell center against volume occupancy,
requires exactly one covering rectangle for each wet surface cell and none for
dry cells, and compares total area. It also checks index winding, normals,
world-space UVs and deterministic repeated extraction. Cases include a rectangle,
disconnected chamber, irregular cave roof, central island, negative coordinates,
scaled lattice with an integer fill elevation, and the maximum-cell basin.
The scene test covers edit invalidation, rebaking and removal during sampling.

The inspected [1920 x 1080 screenshot](evidence/water_mesh/water_lake.png)
shows the bounded excavated lake. The voxel-stepped shoreline remains visible.
These tests do not establish flow, smooth shorelines, multiplayer or long-run
performance. The broader outstanding scope remains in [delivery status](DELIVERY_STATUS.md).

## Reproduce

From the TerraForest project directory:

```text
python tools/build_native.py --addon volumetric_water --target all
python tools/validate.py --test water
python tools/test_native_release.py --addon volumetric_water
python tools/validate.py --test water_integration --gpu
python tools/record_water_mesh_validation.py
```

Reports and tested source/DLL hashes are preserved in `docs/evidence/water_mesh`.
''', encoding='utf-8')
print('Recorded native water rectangle-mesh evidence.')
