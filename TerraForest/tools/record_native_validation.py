"""Record native and 1080p evidence without overwriting historical integration results."""
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[1]
reports = root / 'reports'
evidence = root / 'docs/evidence/native_1080p'
evidence.mkdir(parents=True, exist_ok=True)
names = ['native_runtime.json', 'native_release.json', 'presentation.json', 'scene_soak.json']
data = {name: json.loads((reports / name).read_text()) for name in names}
assert all(value.get('failures', 0) == 0 for value in data.values())
scene = data['scene_soak.json']
assert scene['presentation']['fair_graphical_sample']
for name in names + ['scene_soak.log', 'overview.png', 'after_edit.png', 'pack_smoke.log',
                     'native_build_template_debug.json', 'native_build_template_release.json']:
    shutil.copy2(reports / name, evidence / name)
frame = scene['frame_times']
text = f'''# Native toolchain and fullscreen validation — 2026-09-27

Godot {scene['engine']['string']}, Windows x86-64, Forward+, {scene['adapter']}.
The current scene renders at 1920×1080, exclusive fullscreen, 100% 3D resolution.
Historical results in VALIDATION.md used 1600×900 and are a separate run.

## Completed checks

- Zig 0.16.0 and the supplied API 4.7 prebuilt godot-cpp archive downloaded and verified against pinned SHA-256 digests.
- Debug and release extension DLLs built and loaded in Godot. No godot-cpp source was compiled locally.
- Debug native entity suite: {len(data['native_runtime.json']['checks'])} passing checks. Release DLL in a clean project: {len(data['native_release.json']['checks'])} passing checks.
- Second builds of both variants compiled zero sources and skipped linking.
- Fullscreen capture verified 1920×1080 pixels.
- Full rendered terrain/forest scene: {len(scene['checks'])} passing checks, including excavation, updated collision and four travel cycles.
- Resource pack exported and started with all three required Windows native DLLs beside the pack.

## Measured sample

{frame['count']} uncapped frame samples during the warmed camera view: median {frame['p50_ms']:.3f} ms,
p95 {frame['p95_ms']:.3f} ms, p99 {frame['p99_ms']:.3f} ms, maximum {frame['max_ms']:.3f} ms.
This is a scene sample, not worst-case travel performance, a speedup comparison or multi-hour endurance evidence.

The native entity test runs 100,000 entities for 240 kinematic ticks and outputs a bulk transform buffer.
It does not measure rendered entity population, collision, vehicles or multiplayer capacity.
The first Zig link populated compiler runtime caches; later builds reuse them. These caches are separate from the downloaded godot-cpp libraries.

## Remaining scope

The inherited terrain binary was retained. Existing GDScript streaming and vegetation scheduling have not yet been migrated to C++.
Volumetric water, new road/building/city systems, inventory, authoritative multiplayer and vehicles remain unimplemented.
See WORLD_SYSTEMS_DESIGN.md for the expansion contract and NATIVE_DEVELOPMENT.md for reproducible builds.
Matching standalone Godot export templates are still needed for a standalone executable release.

Raw reports and current captures are in evidence/native_1080p/.
'''
(root / 'docs/TOOLCHAIN_VALIDATION.md').write_text(text, encoding='utf-8')
print('Recorded current native/1080p evidence; historical evidence preserved.')
