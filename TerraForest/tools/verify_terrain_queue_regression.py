"""Run the queue progress test against retained and current backend implementations."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
args = parser.parse_args()
engine = Path(args.godot)
direct = engine.parent / 'godot.windows.opt.tools.64.exe'
if direct.exists():
    engine = direct
baseline = '717deba'
output = root / 'reports/terrain_queue_regression'
output.mkdir(parents=True, exist_ok=True)
build = root / '.build'
build.mkdir(exist_ok=True)
for variant in ['baseline', 'current']:
    with tempfile.TemporaryDirectory(prefix='queue_regression_', dir=build) as temporary:
        project = Path(temporary).resolve()
        assert build.resolve() in project.parents
        addon = project / 'addons/volumetric_terrain'
        (addon / 'bin').mkdir(parents=True)
        for name in ['terrain_backend.gd', 'derived_cache.gd', 'mesh_codec.gd', 'terrain_core.gdextension']:
            shutil.copy2(root / 'addons/volumetric_terrain' / name, addon / name)
        shutil.copy2(root / 'addons/volumetric_terrain/bin/terrain_core.windows.x86_64.dll',
                     addon / 'bin/terrain_core.windows.x86_64.dll')
        if variant == 'baseline':
            (addon / 'terrain_backend.gd').write_bytes(subprocess.check_output([
                'git', 'show', baseline + ':TerraForest/addons/volumetric_terrain/terrain_backend.gd'], cwd=root))
        (project / 'tests').mkdir()
        shutil.copy2(root / 'tests/terrain_queue_progress.gd', project / 'tests/terrain_queue_progress.gd')
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Terrain queue regression"\n')
        run = subprocess.run([str(engine), '--headless', '--path', str(project), '--script',
                              'res://tests/terrain_queue_progress.gd'], capture_output=True, text=True, timeout=60)
        log = run.stdout + '\n' + run.stderr
        (output / (variant + '.log')).write_text(log, encoding='utf-8')
        if re.search(r'(?m)^(SCRIPT ERROR|ERROR:|WARNING: ObjectDB instances leaked)', log):
            raise RuntimeError(log)
        report = json.loads((project / 'reports/terrain_queue_progress.json').read_text())
        (output / (variant + '.json')).write_text(json.dumps(report, indent=2))
        failed = [row['name'] for row in report['checks'] if not row['pass']]
        print(variant, json.dumps(failed), flush=True)
        if variant == 'baseline':
            assert run.returncode == 1 and failed == [
                'retained geometry rechecks lighting after intervening edits',
                'unaffected mesh completes with its original dependency stamp']
        else:
            assert run.returncode == 0 and not failed
