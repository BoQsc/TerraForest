"""Run graphical full-scene tests and store a machine-readable performance report."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import re

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
p.add_argument('--renderer',default='forward_plus',choices=['forward_plus','mobile','gl_compatibility'])
p.add_argument('--cycles',type=int,default=4)
p.add_argument('--uncapped',action='store_true')
args=p.parse_args()
if not args.godot:
    p.error('Specify --godot PATH')
engine=Path(args.godot)
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():
    engine=direct
(root/'reports').mkdir(exist_ok=True)
with (root/'reports/scene_soak.log').open('w',encoding='utf-8') as log:
    result=subprocess.run([str(engine),'--path',str(root),'--rendering-method',args.renderer,'--script','res://tests/scene_soak.gd','--','--temporary','--max-fps=60',f'--cycles={args.cycles}',*(['--uncapped'] if args.uncapped else [])],stdout=log,stderr=subprocess.STDOUT,timeout=max(480,args.cycles*100))
text=(root/'reports/scene_soak.log').read_text(encoding='utf-8')
print(text[-18000:])
raise SystemExit(1 if result.returncode or re.search(r'SCRIPT ERROR|ERROR:|FAIL |ObjectDB instances leaked',text) else 0)
