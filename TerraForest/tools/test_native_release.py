"""Load the release DLL in a clean Godot project and run the native API checks."""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from bootstrap_native import ROOT

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
parser.add_argument('--addon',choices=['world_runtime','volumetric_water'],default='world_runtime')
parser.add_argument('--test',choices=['native_runtime','water','world_archive','world_persistence'])
args=parser.parse_args()
if not args.godot:parser.error('Specify --godot PATH')
engine=Path(args.godot)
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():engine=direct
build=ROOT/'.build'
build.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='release_smoke_',dir=build) as temporary:
    project=Path(temporary).resolve()
    assert build.resolve() in project.parents
    addon=project/'addons'/args.addon
    (addon/'bin').mkdir(parents=True)
    source=ROOT/'addons'/args.addon
    library=f'{args.addon}.windows.template_release.x86_64.dll'
    shutil.copy2(source/'bin'/library,addon/'bin'/library)
    descriptor=(source/(args.addon+'.gdextension')).read_text().replace('template_debug','template_release')
    (addon/(args.addon+'.gdextension')).write_text(descriptor)
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="TerraForest Native Release Test"\n')
    (project/'tests').mkdir()
    test=args.test or ('water' if args.addon=='volumetric_water' else 'native_runtime')
    if test in ['world_archive','world_persistence']:
        for name in ['world_runtime','volumetric_water']:
            destination=project/'addons'/name
            shutil.copytree(ROOT/'addons'/name,destination,dirs_exist_ok=True)
            descriptor=destination/(name+'.gdextension')
            descriptor.write_text(descriptor.read_text().replace('template_debug','template_release'))
    if test in ['water','world_persistence']:
        terrain=project/'addons/volumetric_terrain'
        if test=='world_persistence':
            shutil.copytree(ROOT/'addons/volumetric_terrain',terrain)
            descriptor=terrain/'terrain_core.gdextension'
            descriptor.write_text(descriptor.read_text().replace('terrain_core.windows.x86_64.dll','terrain_core.windows.template_release.x86_64.dll'))
        else:
            terrain.mkdir()
            for name in ['terrain_core.gdextension','mesh_codec.gd']:
                shutil.copy2(ROOT/'addons/volumetric_terrain'/name,terrain/name)
            shutil.copytree(ROOT/'addons/volumetric_terrain/bin',terrain/'bin')
    shutil.copy2(ROOT/'tests'/(test+'.gd'),project/'tests'/(test+'.gd'))
    run=subprocess.run([str(engine),'--headless','--path',str(project),'--script',f'res://tests/{test}.gd'],capture_output=True,text=True,timeout=120)
    log=run.stdout+'\n'+run.stderr
    print(log)
    report_name={'water':'water_release','native_runtime':'native_release'}.get(test,test+'_release')
    (ROOT/'reports'/(report_name+'.log')).write_text(log,encoding='utf-8')
    report=json.loads((project/'reports'/(test+'.json')).read_text())
    report['library']=library
    (ROOT/'reports'/(report_name+'.json')).write_text(json.dumps(report,indent=2))
    errors=re.search(r'(?m)^(?:SCRIPT ERROR|ERROR:|FAIL |WARNING: ObjectDB instances leaked)',log)
    raise SystemExit(1 if run.returncode or report['failures'] or errors else 0)
