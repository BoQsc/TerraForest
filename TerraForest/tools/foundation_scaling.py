"""Run sequential integrated mining pressure tests; retain failures as evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
parser.add_argument('--scales', nargs='+', type=int, choices=[1, 4, 16], default=[1, 4, 16])
parser.add_argument('--terrain', choices=['legacy','snapshot','bricks'], default='legacy')
args = parser.parse_args()
engine = Path(args.godot)
direct = engine.parent / 'godot.windows.opt.tools.64.exe'
if direct.exists():
    engine = direct
results = []
for scale in args.scales:
    prefix='foundation' if args.terrain=='legacy' else 'foundation_'+args.terrain
    output = root / 'reports' / f'{prefix}_scale_{scale}'
    output.mkdir(parents=True, exist_ok=True)
    sources = [root / 'tests/foundation_mining.gd', Path(__file__).resolve()]
    sources += sorted((root / 'addons/volumetric_terrain').rglob('*.gd'))
    sources += sorted((root / 'addons/volumetric_terrain/native').glob('*.cpp'))
    sources += sorted((root / 'addons/volumetric_terrain/native').rglob('*.hpp'))
    sources += sorted((root / 'addons/volumetric_terrain/native').rglob('*.h'))
    sources += sorted((root / 'addons/volumetric_terrain/bin').glob('*.dll'))
    manifest = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sources}
    (output / 'source_hashes.json').write_text(json.dumps(manifest, indent=2))
    shutil.copy2(root / 'tests/foundation_mining.gd', output / 'workload.gd.txt')
    for name in ['foundation_mining.json', 'foundation_mining.frames.csv']:
        # Exact generated files only; never carry an earlier result into a timeout.
        (root / 'reports' / name).unlink(missing_ok=True)
    command = [str(engine), '--path', str(root), '--script',
               'res://tests/foundation_mining.gd', '--', f'--foundation-scale={scale}']
    if args.terrain!='legacy': command.append('--brick-terrain' if args.terrain=='bricks' else '--snapshot-terrain')
    (output/'launch.json').write_text(json.dumps({'terrain':args.terrain,'command':command},indent=2))
    with (output / 'run.log').open('w', encoding='utf-8') as log:
        try:
            run = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                 timeout=180 + scale * 90)
            code = run.returncode
        except subprocess.TimeoutExpired:
            code = 124
    for name in ['foundation_mining.json', 'foundation_mining.frames.csv']:
        source = root / 'reports' / name
        if source.exists():
            shutil.copy2(source, output / name)
    text = (output / 'run.log').read_text(encoding='utf-8')
    errors = re.findall(r'(?m)^(?:SCRIPT ERROR|ERROR:|WARNING: ObjectDB instances leaked).*', text)
    item = {'scale': scale, 'terrain':args.terrain, 'exit_code': code, 'runtime_errors': errors}
    results.append(item)
    print(json.dumps(item), flush=True)
    # Budget failures are valid evidence. Script failures/timeouts require repair.
    if errors or code not in [0, 1]:
        break
(root / 'reports/foundation_scaling.json').write_text(json.dumps(results, indent=2))
raise SystemExit(0 if all(row['exit_code'] == 0 and not row['runtime_errors'] for row in results) else 1)
