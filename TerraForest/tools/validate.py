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
parser.add_argument('--timeout',type=int,default=180)
parser.add_argument('--test',choices=['integration','persistence','native_runtime','presentation','water','water_integration','world_archive','world_persistence','terrain_native','terrain_planner','terrain_collision','terrain_collision_profile','structures','block_lattice','block_worker','building_collision_profile','building_collision_stream','building_readiness','block_regions','block_region_store','block_region_io','block_region_checkpoints','block_region_bootstrap','partial_region_storage','region_world_archive','static_placements','structure_persistence','structure_world'],default='integration')
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
try:
    result=subprocess.run(command,capture_output=True,text=True,timeout=args.timeout)
except subprocess.TimeoutExpired as error:
    def decoded(value):return value.decode('utf-8',errors='replace') if isinstance(value,bytes) else (value or '')
    log=decoded(error.stdout)+'\n'+decoded(error.stderr)
    (ROOT/'reports'/(args.test+('_gpu.log' if args.gpu else '.log'))).write_text(log,encoding='utf-8')
    print(log[-16000:])
    raise SystemExit(f'Test exceeded {args.timeout}s; process terminated and captured output retained.')
log=result.stdout+'\n'+result.stderr
(ROOT/'reports'/(args.test+('_gpu.log' if args.gpu else '.log'))).write_text(log,encoding='utf-8')
print(log if len(log)<=16000 else log[:7000]+'\n[Full output retained in reports; repeated diagnostics omitted]\n'+log[-7000:])
errors=re.findall(r'(?m)^(?:SCRIPT ERROR|ERROR:|FAIL |WARNING: ObjectDB instances leaked)',log)
raise SystemExit(1 if result.returncode or errors else 0)
