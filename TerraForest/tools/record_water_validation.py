"""Preserve native water correctness, scene validation and visual evidence."""
from pathlib import Path
import json
import shutil

root=Path(__file__).resolve().parents[1]
reports=root/'reports'
evidence=root/'docs/evidence/water'
evidence.mkdir(parents=True,exist_ok=True)
native=json.loads((reports/'water.json').read_text())
release=json.loads((reports/'water_release.json').read_text())
scene=json.loads((reports/'water_integration.json').read_text())
assert not any(r['failures'] for r in [native,release,scene])
assert scene['presentation']['fair_graphical_sample']
for name in ['water.json','water.log','water_release.json','water_release.log','water_integration.json',
             'water_integration_gpu.log','water_lake.png','isolation.json','integration.json','pack_smoke.log',
             'volumetric_water_build_template_debug.json','volumetric_water_build_template_release.json']:
    shutil.copy2(reports/name,evidence/name)
frame=scene['frame_times']
text=f'''# Static volumetric water validation — 2026-09-27

This report covers the first bounded static-lake implementation, not the full requested world-system expansion.

## Correctness

- Native debug: {len(native['checks'])} checks passed.
- Native release DLL loaded in a clean project: {len(release['checks'])} checks passed.
- Real terrain/forest scene: {len(scene['checks'])} checks passed.
- Water addon starts and bakes a density field without either terrain or forest installed.
- Existing terrain/forest integration: 31 checks passed after adding water hooks.
- Resource pack starts with five external Windows DLLs (terrain, two runtime variants, two water variants).

Tests cover allocation caps, invalid dimensions/coordinates/density, immutable publication, finite depth queries,
open-boundary rejection, blocked seeds, disconnected chambers, water below a cave roof, negative coordinates,
scratch reclamation, actual native terrain sampling, revision and cancellation mismatch, edit invalidation,
rebaking and removal while sampling. Water data in the demo basin occupies 20,480 resident bytes;
this excludes rendering resources and scene/bookkeeping overhead.

## Measured costs

Headless debug measurements: 262,144-cell flood bake {native['large_bake_ms']:.3f} ms; actual terrain sampling/bake
{native['terrain_sample_ms']:.3f} ms across {native['terrain_slices']} bounded slices. These are CPU test timings,
not guarantees for every machine, and not per-frame fluid simulation costs.

The graphical run used {scene['engine']['string']}, Forward+ on the GTX 1060 Max-Q, **1920×1080 exclusive fullscreen**,
100% 3D scale. In a fixed warmed view of one lake and the surrounding forest, {frame['count']} uncapped frame samples:

| Median | p95 | p99 | Maximum |
| --- | --- | --- | --- |
| {frame['p50_ms']:.3f} ms | {frame['p95_ms']:.3f} ms | {frame['p99_ms']:.3f} ms | {frame['max_ms']:.3f} ms |

The maximum is retained rather than discarded. This short sample excludes bake/travel timing and is not a matched baseline speedup,
multi-hour soak, multiplayer capacity result, or evidence of worst-case frame headroom.

## Visual and release limits

The actual screenshot in evidence/water/water_lake.png was inspected. It shows the excavated basin and bounded water surface.
Shorelines remain visibly voxel-stepped; the shader is opaque with lighting ripples and no refraction/underwater effect.
This is a development feature, not a finished water visual treatment.

Lake definitions now share a compound snapshot with terrain; see WORLD_STORAGE.md and STORAGE_VALIDATION.md for persistence and recovery evidence.
There is no water bake cache, automatic lake placement, mass-conserving flow, swimming, buoyancy or water replication yet.
Opening the basin rejects a rebake instead of simulating drainage. A blocked seed also rejects the bake.

Builds use Zig and the pinned prebuilt godot-cpp libraries; no local godot-cpp compilation was performed.
Run the commands in addons/volumetric_water/README.md to reproduce these checks.
'''
(root/'docs/WATER_VALIDATION.md').write_text(text,encoding='utf-8')
print('Recorded static-lake evidence and limitations.')
