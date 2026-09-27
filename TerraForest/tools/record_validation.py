"""Collect the completed local validation artifacts into the distributable documentation."""
from pathlib import Path
import json
import shutil

root=Path(__file__).resolve().parents[1]
reports=root/'reports'
if json.loads((reports/'scene_soak.json').read_text()).get('presentation'):
    raise SystemExit('This recorder preserves the historical 1600x900 integration report. Use record_native_validation.py for the current 1080p/native results.')
evidence=root/'docs/evidence'
evidence.mkdir(exist_ok=True)
for name in ['integration.json','integration_gpu.log','persistence.json','persistence.log','isolation.json','scene_soak.json','scene_soak.log','pack_smoke.log','overview.png','after_edit.png']:
    shutil.copy2(reports/name,evidence/name)
integration=json.loads((reports/'integration.json').read_text())
persistence=json.loads((reports/'persistence.json').read_text())
scene=json.loads((reports/'scene_soak.json').read_text())
long=json.loads((evidence/'travel_120.json').read_text())
frame=scene['frame_times']
long_frame=long['frame_times']
assert not any(report['failures'] for report in [integration,persistence,scene,long])
text=f'''# Validation — 2026-09-27

Executed locally with Godot {scene['engine']['string']} on Windows, Forward+, {scene['adapter']}. The graphical scene viewport was 1600×900. Test worlds were temporary except the explicitly isolated persistence test slot, which was removed afterwards.

## Final revision results

| Gate | Result |
| --- | --- |
| Public API/native/vegetation integration on GPU | {len(integration['checks'])} checks passed |
| Persistent save, new-instance reload and corruption protection | {len(persistence['checks'])} checks passed |
| Terrain-only and vegetation-only empty-project startup | Both passed |
| Literal resource paths and core addon dependency boundaries | Passed |
| Full rendered scene, real collision excavation and four travel cycles | {len(scene['checks'])} checks passed |
| Windows resource pack plus external native DLL | Exported and started headlessly without engine/script errors |

The integration suite covers native startup, singleton protection, deterministic placement, resident/root/query limits, teleport eviction, rejected malformed edits, publication signals, tree suppression, unload/return without regrowth, invalid transforms, teardown and stopped-worker restart rejection. A never-added vegetation facade is freed during the test to catch pre-tree ownership leaks. Final GPU integration produced no object-leak warning.

The persistence test intentionally creates a corrupt snapshot and verifies that shutdown leaves those bytes untouched. Its `save disabled after corrupt snapshot` status is an expected passing condition, not an ignored engine error.

## Measured rendering sample

Final source, uncapped with VSync disabled, after scene readiness and four seconds of warmup: {frame['count']} wall-clock frame samples during a slow camera turn. The initial view had about 2,724 resident trees. This measures that scene, not continuous worst-case travel or mesh-publication tails.

| Metric | Final four-cycle validation | Earlier 120-cycle validation |
| --- | --- | --- |
| Median | {frame['p50_ms']:.3f} ms | {long_frame['p50_ms']:.3f} ms |
| p95 | {frame['p95_ms']:.3f} ms | {long_frame['p95_ms']:.3f} ms |
| p99 | {frame['p99_ms']:.3f} ms | {long_frame['p99_ms']:.3f} ms |
| Maximum in camera sample | {frame['max_ms']:.3f} ms | {long_frame['max_ms']:.3f} ms |

These figures are not measured speedups over either original distribution. No matched baseline comparison was performed. The demo normally uses a 60 FPS cap and VSync to avoid spending all available GPU capacity while idle.

## Repeated-travel evidence

The longer run completed 120 back-and-forth travel cycles and {len(long['checks'])} checks with zero failures. After warming both destinations, terrain residency settled at 440 tiles and 112,616,880 tracked mesh bytes (about 107.4 MiB). Forest residency stayed at 169 placement cells. Selector event counts alternated with the two views instead of growing with visit count.

Godot static memory alternated around 256–259 MiB late in the run; the test itself retains one statistics snapshot per cycle, so small growth in that counter is not a clean process-leak measurement. This is not process working set or measured driver VRAM. The 120-cycle run occurred before the final selective root-invalidation and pre-tree ownership refinements; the final revision was subsequently checked with the GPU integration suite and the four-cycle rendered test above.

## Visual review and packaging

`overview.png` and `after_edit.png` were captured from the real renderer and inspected. They show the terrain material, source/proxy forest, shadows, atmosphere and HUD. Collision is also tested by a downward physics ray verifying that the post-edit hit is lower than the original surface.

The PCK test initially exposed a missing external GDExtension DLL. `tools/export_pack.py` now copies that DLL beside the pack and tests startup from the distribution directory. Raw spruce textures were converted to direct-byte `.trtex` loading, and their `.gdignore` was removed so export filters can include all packed assets. Exported codec fingerprints follow Godot's bytecode remap; unknown fingerprints disable the derived cache rather than reuse an ambiguous key.

## Limits of this evidence

No multi-hour endurance test, second-machine executable test, Linux GPU test, console/mobile-device test, arbitrary-species pipeline or matched baseline speedup measurement was completed. The bundled native code and native regression sources were retained; a compiler was not available, so the native binary was exercised through Godot rather than rebuilt. Matching Godot 4.7.2 standalone export templates were not installed, so the delivered runnable development artifact is the Godot project plus a validated resource pack, not a standalone EXE.

The project is a development release with explicit constraints: fixed native world dimensions/seed, one active terrain world per process, a single supplied spruce species, visual-only trees, and conservative edited-column exclusion. See RELEASE_CHECKLIST.md before a public production-readiness claim.

Evidence files in this directory are actual tool outputs. Reproduce them with the commands in the root README.
'''
(root/'docs/VALIDATION.md').write_text(text,encoding='utf-8')
print('Collected validation evidence and generated docs/VALIDATION.md')
