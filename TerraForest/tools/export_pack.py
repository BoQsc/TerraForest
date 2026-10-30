"""Export and validate a resource pack without requiring platform export templates."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys
import configparser
import json
import time
from resource_limits import distribution_size, evaluate, load_budgets, require_free_space

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
p.add_argument('--staging-directory',type=Path)
args=p.parse_args()
if not args.godot:
    p.error('Specify --godot PATH')
require_free_space(root, load_budgets()['redistributable_limit_bytes'])
engine=Path(args.godot)
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():engine=direct
if subprocess.call([str(engine),'--headless','--path',str(root),'--script','res://tools/bake_first_person_meshes.gd']):
    sys.exit(1)
if subprocess.call([str(engine),'--headless','--path',str(root),'--script','res://tools/ensure_item_icons.gd']):
    sys.exit(1)
(root/'dist').mkdir(exist_ok=True)
(root/'reports').mkdir(exist_ok=True)
installed_pack=root/'dist/TerraForest.pck'
staging=args.staging_directory.resolve() if args.staging_directory else root/'dist'
staging.mkdir(parents=True,exist_ok=True)
pack=staging/'TerraForest.pending.pck'
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
prospective_bytes = pack.stat().st_size
for descriptor in (root/'addons').rglob('*.gdextension'):
    config=configparser.ConfigParser()
    config.read(descriptor,encoding='utf-8')
    for feature,value in config.items('libraries'):
        if feature.startswith('windows.') and feature.endswith('.x86_64'):
            library=value.strip('"')
            if not library.startswith('res://'):
                raise ValueError('Expected project-local native library')
            source=(root/library[6:]).resolve()
            if root not in source.parents:
                raise ValueError('Native library escapes project')
            prospective_bytes += source.stat().st_size
if evaluate(distribution_bytes=prospective_bytes)['redistributable']['status'] == 'exceeded':
    raise ValueError('Prospective pack and native libraries exceed 5 GB; installed pack/libraries retained')
for descriptor in (root/'addons').rglob('*.gdextension'):
    config=configparser.ConfigParser()
    config.read(descriptor,encoding='utf-8')
    for feature,value in config.items('libraries'):
        if feature.startswith('windows.') and feature.endswith('.x86_64'):
            path=value.strip('"')
            if not path.startswith('res://'):raise ValueError('Expected project-local native library')
            library=Path(path[6:])
            source=(root/library).resolve()
            destination=(staging/library).resolve()
            if root not in source.parents or staging.resolve() not in destination.parents:
                raise ValueError('Native library escapes export directory')
            destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source,destination)
            libraries.add(str(library))
notices=[Path('addons/structures/MESHOPTIMIZER_LICENSE.txt'),
         Path('assets/branding/GODOT_LOGO_LICENSE.txt')]
for notice in notices:
    destination=staging/notice
    destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(root/notice,destination)
size = distribution_size(staging, pack)
budget = evaluate(distribution_bytes=size)['redistributable']
(root/'reports/distribution_budget.json').write_text(json.dumps(dict(bytes=size, budget=budget), indent=2))
if budget['status'] == 'exceeded':
    raise ValueError('Distributable content exceeds the 5 GB budget; existing installed pack retained')
if budget['status'] == 'warning':
    print('WARNING: Distributable content has reached its size warning budget')
smoke=subprocess.run([str(engine),'--headless','--path',str(staging),'--main-pack',str(pack),'--quit-after','180','--','--temporary'],cwd=staging,capture_output=True,text=True,timeout=60)
smoke_log=smoke.stdout+'\n'+smoke.stderr
(root/'reports/pack_smoke.log').write_text(smoke_log,encoding='utf-8')
print(smoke_log[-4000:])
if smoke.returncode or 'ERROR:' in smoke_log or 'SCRIPT ERROR' in smoke_log:
    sys.exit(1)
if staging!=root/'dist':
    if shutil.disk_usage(root/'dist').free<pack.stat().st_size+16*1024*1024:
        raise OSError('Insufficient space to install the staged pack safely; existing pack retained')
    for library in libraries:
        destination=root/'dist'/library
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(staging/library,destination)
    for notice in notices:
        destination=root/'dist'/notice
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(staging/notice,destination)
    pending=root/'dist/TerraForest.pending.pck'
    shutil.copy2(pack,pending)
    pending.replace(installed_pack)
else:
    pack.replace(installed_pack)
usage_metadata = dict(schema=1, bytes=distribution_size(root/'dist'), pack_bytes=installed_pack.stat().st_size,
                      measured_at=time.time())
usage_pending = root/'dist/usage_content.pending.json'
usage_pending.write_text(json.dumps(usage_metadata), encoding='utf-8')
usage_pending.replace(root/'dist/usage_content.json')
print(f'PASS exported pack starts with {len(libraries)} external native libraries; keep dist/addons beside the PCK')
