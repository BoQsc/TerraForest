"""Compare the typed terrain bridge with the published legacy DLL and test release isolation."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
parser.add_argument('--legacy-dll', type=Path, help='Use a retained legacy DLL instead of reading the published Git commit')
args = parser.parse_args()
if not args.godot: parser.error('Specify --godot PATH')
engine = Path(args.godot)
if (engine.parent / 'godot.windows.opt.tools.64.exe').exists():
    engine = engine.parent / 'godot.windows.opt.tools.64.exe'
baseline = 'e1181687e14e2dac03598af2e35044d47917e721'
legacy = args.legacy_dll.read_bytes() if args.legacy_dll else subprocess.check_output([
    'git', 'show', baseline + ':TerraForest/addons/volumetric_terrain/bin/terrain_core.windows.x86_64.dll'], cwd=root)
build = root / '.build'
build.mkdir(exist_ok=True)
reports = root / 'reports'
reports.mkdir(exist_ok=True)
results = {}
for variant in ['legacy', 'template_debug', 'template_release']:
    with tempfile.TemporaryDirectory(prefix='terrain_bridge_', dir=build) as temporary:
        project = Path(temporary).resolve()
        assert build.resolve() in project.parents
        addon = project / 'addons/volumetric_terrain'
        (addon / 'bin').mkdir(parents=True)
        name = 'terrain_core.windows.template_release.x86_64.dll' if variant == 'template_release' else 'terrain_core.windows.x86_64.dll'
        data = legacy if variant == 'legacy' else (root / 'addons/volumetric_terrain/bin' / name).read_bytes()
        (addon / 'bin/terrain.dll').write_bytes(data)
        (addon / 'terrain_core.gdextension').write_text('''[configuration]
entry_symbol = "terrain_library_init"
compatibility_minimum = "4.7"
reloadable = false
[libraries]
windows.debug.x86_64 = "res://addons/volumetric_terrain/bin/terrain.dll"
windows.release.x86_64 = "res://addons/volumetric_terrain/bin/terrain.dll"
''')
        shutil.copy2(root / 'addons/volumetric_terrain/mesh_codec.gd', addon / 'mesh_codec.gd')
        (project / 'tests').mkdir()
        shutil.copy2(root / 'tests/terrain_native.gd', project / 'tests/terrain_native.gd')
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Terrain Bridge Test"\n')
        command = [str(engine), '--headless', '--path', str(project), '--script', 'res://tests/terrain_native.gd']
        if variant == 'legacy': command += ['--', '--parity-only']
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        log = result.stdout + '\n' + result.stderr
        (reports / f'terrain_bridge_{variant}.log').write_text(log, encoding='utf-8')
        if result.returncode or re.search(r'(?m)^(SCRIPT ERROR|ERROR:|FAIL |WARNING: ObjectDB instances leaked)', log):
            print(log[-10000:])
            raise SystemExit(1)
        report = json.loads((project / 'reports/terrain_native.json').read_text())
        assert not report['failures']
        report['library_sha256'] = hashlib.sha256(data).hexdigest()
        results[variant] = report
        print(f'PASS {variant}: {len(report["checks"])} checks')
for variant in ['template_debug', 'template_release']:
    for key, expected in results['legacy']['fingerprints'].items():
        assert results[variant]['fingerprints'][key] == expected, (variant, key, 'legacy byte parity mismatch')
report = {'baseline_commit': baseline if not args.legacy_dll else None, 'variants': results,
          'byte_parity': True, 'scope': 'Native worlds only; facade, cache ownership and multiplayer still require separate validation'}
(reports / 'terrain_bridge.json').write_text(json.dumps(report, indent=2))
print('PASS all field, snapshot and mesh fingerprints match the published legacy DLL')
