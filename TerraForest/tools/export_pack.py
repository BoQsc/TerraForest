"""Export and validate a resource pack without requiring platform export templates."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys
import configparser

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
args=p.parse_args()
if not args.godot:
    p.error('Specify --godot PATH')
engine=Path(args.godot)
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():engine=direct
(root/'dist').mkdir(exist_ok=True)
(root/'reports').mkdir(exist_ok=True)
pack=root/'dist/TerraForest.pck'
result=subprocess.run([str(engine),'--headless','--path',str(root),'--export-pack','Windows Desktop',str(pack)],capture_output=True,text=True,timeout=180)
log=result.stdout+'\n'+result.stderr
(root/'reports/export.log').write_text(log,encoding='utf-8')
if result.returncode or not pack.exists() or 'ERROR:' in log:
    print(log[-6000:])
    sys.exit(1)
print(f'Created {pack} ({pack.stat().st_size:,} bytes)')
# Dynamic libraries cannot be loaded from inside a PCK. Pack-only exports do not
# copy GDExtension libraries the way full executable exports do.
libraries=set()
for descriptor in (root/'addons').rglob('*.gdextension'):
    config=configparser.ConfigParser()
    config.read(descriptor,encoding='utf-8')
    for feature,value in config.items('libraries'):
        if feature.startswith('windows.') and feature.endswith('.x86_64'):
            path=value.strip('"')
            if not path.startswith('res://'):raise ValueError('Expected project-local native library')
            library=Path(path[6:])
            source=(root/library).resolve()
            destination=(root/'dist'/library).resolve()
            if root not in source.parents or (root/'dist').resolve() not in destination.parents:
                raise ValueError('Native library escapes export directory')
            destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source,destination)
            libraries.add(str(library))
smoke=subprocess.run([str(engine),'--headless','--path',str(root/'dist'),'--main-pack',str(pack),'--quit-after','180','--','--temporary'],cwd=root/'dist',capture_output=True,text=True,timeout=60)
smoke_log=smoke.stdout+'\n'+smoke.stderr
(root/'reports/pack_smoke.log').write_text(smoke_log,encoding='utf-8')
print(smoke_log[-4000:])
if smoke.returncode or 'ERROR:' in smoke_log or 'SCRIPT ERROR' in smoke_log:
    sys.exit(1)
print(f'PASS exported pack starts with {len(libraries)} external native libraries; keep dist/addons beside the PCK')
