"""Launch TerraForest with an existing Godot 4.7 executable; no installation required."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
parser.add_argument('--renderer', choices=['forward_plus','mobile','gl_compatibility'], default='forward_plus')
parser.add_argument('--temporary', action='store_true')
args, extra = parser.parse_known_args()
if not args.godot:
    parser.error('Pass --godot PATH or set GODOT_EXE to an existing Godot executable')
engine=Path(args.godot)
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():
    engine=direct
raise SystemExit(subprocess.call([str(engine), '--path', str(ROOT), '--rendering-method', args.renderer, '--', *(['--temporary'] if args.temporary else []), *extra]))
