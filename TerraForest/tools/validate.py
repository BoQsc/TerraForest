"""Run real-engine integration checks, retain logs, and fail on script/runtime errors."""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
parser.add_argument('--gpu',action='store_true')
parser.add_argument('--test',choices=['integration','persistence','native_runtime','presentation','water','water_integration','world_archive','world_persistence'],default='integration')
args=parser.parse_args()
if not args.godot:
    parser.error('Godot is required; use --godot PATH')
engine=Path(args.godot)
# Steam's small launcher detaches; use the actual engine so exit codes/logs are observed.
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():
    engine=direct
(ROOT/'reports').mkdir(exist_ok=True)
command=[str(engine),'--path',str(ROOT),'--script',f'res://tests/{args.test}.gd']
if not args.gpu:
    command.append('--headless')
result=subprocess.run(command,capture_output=True,text=True,timeout=180)
log=result.stdout+'\n'+result.stderr
(ROOT/'reports'/(args.test+('_gpu.log' if args.gpu else '.log'))).write_text(log,encoding='utf-8')
print(log if len(log)<=16000 else log[:7000]+'\n[Full output retained in reports; repeated diagnostics omitted]\n'+log[-7000:])
errors=re.findall(r'(?m)^(?:SCRIPT ERROR|ERROR:|FAIL |WARNING: ObjectDB instances leaked)',log)
raise SystemExit(1 if result.returncode or errors else 0)
