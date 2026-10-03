"""Start a temporary human playtest and retain its launch details and engine log."""
from pathlib import Path
import argparse
import datetime
import json
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', type=Path)
args = parser.parse_args()
candidates = [args.godot, os.environ.get('GODOT_EXE'), shutil.which('godot'),
              Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) /
              'Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe']
engine = next((Path(p) for p in candidates if p and Path(p).is_file()), None)
if engine is None:
    parser.error('Pass --godot PATH or set GODOT_EXE')
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
folder = ROOT / 'reports' / 'playtests' / stamp
folder.mkdir(parents=True)
command = [str(engine), '--path', str(ROOT), '--rendering-method', 'forward_plus',
           'res://demo/world.tscn', '--', '--temporary', '--human-playtest', '--max-fps=60']
revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True,
                          text=True, check=True).stdout.strip()
with (folder / 'engine.log').open('w', encoding='utf-8') as log:
    process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                               creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
manifest = {'pid': process.pid, 'revision': revision, 'command': command,
            'temporary_world': True, 'experimental_snapshot_terrain': False,
            'status': 'started; readiness and presentation must be verified in engine.log'}
(folder / 'launch.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'pid': process.pid, 'log': str(folder / 'engine.log'),
                  'manifest': str(folder / 'launch.json')}, indent=2), flush=True)
