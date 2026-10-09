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
parser.add_argument('--addon',choices=['world_runtime','volumetric_water','volumetric_terrain','structures'],default='world_runtime')
parser.add_argument('--region-storage',action='store_true',help='Exercise structure_persistence through the native region archive')
parser.add_argument('--test',choices=['terrain_locality_probe','terrain_region_cache','terrain_mesh_pressure','native_runtime','water','world_archive','world_persistence','terrain_planner','terrain_collision','block_lattice','block_worker','block_texture_sets','building_collision_profile','building_collision_stream','building_readiness','block_regions','block_region_store','block_region_io','block_region_checkpoints','block_region_bootstrap','partial_region_storage','region_world_archive','region_archive_reads','region_checkpoint_retention','model_transfer_scheduler','model_scheduler_pressure','model_world_bootstrap','model_focus_paging','model_focus_discovery','block_pager','block_pager_stress','region_metadata','structures','static_placements','static_model_regions','model_region_store','model_region_metadata','model_admission_pressure','model_incremental_admission','model_admission_history','model_incremental_retirement','structure_persistence','model_paging_lifecycle','settlement_network'])
args=parser.parse_args()
if args.region_storage and args.test!='structure_persistence':parser.error('--region-storage requires --test structure_persistence')
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
    module='terrain_core' if args.addon=='volumetric_terrain' else args.addon
    library=f'{module}.windows.template_release.x86_64.dll'
    shutil.copy2(source/'bin'/library,addon/'bin'/library)
    descriptor=(source/(module+'.gdextension')).read_text().replace('template_debug','template_release')
    if args.addon=='volumetric_terrain':descriptor=descriptor.replace('terrain_core.windows.x86_64.dll',library)
    (addon/(module+'.gdextension')).write_text(descriptor)
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="TerraForest Native Release Test"\n')
    (project/'tests').mkdir()
    test=args.test or {'volumetric_water':'water','volumetric_terrain':'terrain_planner','structures':'structures'}.get(args.addon,'native_runtime')
    if test=='terrain_planner':
        shutil.copy2(ROOT/'tests/reference_terrain_planner.gd',project/'tests/reference_terrain_planner.gd')
    if test=='terrain_locality_probe':
        shutil.copy2(source/'mesh_codec.gd',addon/'mesh_codec.gd')
    if test in ['terrain_mesh_pressure','terrain_region_cache']:
        shutil.copy2(source/'mesh_codec.gd',addon/'mesh_codec.gd')
        fixture=Path('docs/evidence/foundation_mining/scale_16/foundation_mining.json.gz')
        (project/fixture).parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/fixture,project/fixture)
    if test=='terrain_collision':
        for name in ['mesh_codec.gd','collision_reuse.gd']:
            shutil.copy2(source/name,addon/name)
    if args.addon=='structures':
        shutil.copytree(source/'prefabs',addon/'prefabs')
        shutil.copytree(source/'textures',addon/'textures')
        if test in ['region_world_archive','model_world_bootstrap','model_focus_paging','model_focus_discovery']:
            for name in ['structures_world.gd','material_startup.gd']:
                shutil.copy2(source/name,addon/name)
    if test in ['block_lattice','block_texture_sets']:
        shutil.copytree(ROOT/'tests/fixtures',project/'tests/fixtures')
    if test in ['region_world_archive','region_archive_reads','region_checkpoint_retention','model_transfer_scheduler','model_scheduler_pressure','model_world_bootstrap','model_focus_paging','model_focus_discovery','block_pager','block_pager_stress']:
        destination=project/'addons/world_runtime'
        shutil.copytree(ROOT/'addons/world_runtime',destination,dirs_exist_ok=True)
        descriptor=destination/'world_runtime.gdextension'
        descriptor.write_text(descriptor.read_text().replace('template_debug','template_release'))
    if test in ['world_archive','world_persistence','structure_persistence','model_paging_lifecycle','settlement_network','region_metadata']:
        for name in (['world_runtime','volumetric_water','structures'] if test in ['structure_persistence','model_paging_lifecycle','settlement_network','region_metadata'] else ['world_runtime','volumetric_water']):
            destination=project/'addons'/name
            shutil.copytree(ROOT/'addons'/name,destination,dirs_exist_ok=True)
            descriptor=destination/(name+'.gdextension')
            descriptor.write_text(descriptor.read_text().replace('template_debug','template_release'))
    if test in ['water','world_persistence','structure_persistence','model_paging_lifecycle','settlement_network','region_metadata']:
        terrain=project/'addons/volumetric_terrain'
        if test in ['world_persistence','structure_persistence','model_paging_lifecycle','settlement_network','region_metadata']:
            shutil.copytree(ROOT/'addons/volumetric_terrain',terrain)
            descriptor=terrain/'terrain_core.gdextension'
            descriptor.write_text(descriptor.read_text().replace('terrain_core.windows.x86_64.dll','terrain_core.windows.template_release.x86_64.dll'))
        else:
            terrain.mkdir()
            for name in ['terrain_core.gdextension','mesh_codec.gd']:
                shutil.copy2(ROOT/'addons/volumetric_terrain'/name,terrain/name)
            shutil.copytree(ROOT/'addons/volumetric_terrain/bin',terrain/'bin')
    shutil.copy2(ROOT/'tests'/(test+'.gd'),project/'tests'/(test+'.gd'))
    display=['--windowed','--resolution','960x540','--rendering-method','forward_plus'] if test=='block_texture_sets' else ['--headless']
    command=[str(engine),*display,'--path',str(project),'--script',f'res://tests/{test}.gd']
    if args.region_storage:command+=['--','--region-storage']
    run=subprocess.run(command,capture_output=True,text=True,timeout=180 if args.region_storage else 120)
    log=run.stdout+'\n'+run.stderr
    print(log)
    result_test='structure_region_persistence' if args.region_storage else test
    report_name={'water':'water_release','native_runtime':'native_release'}.get(result_test,result_test+'_release')
    (ROOT/'reports'/(report_name+'.log')).write_text(log,encoding='utf-8')
    report=json.loads((project/'reports'/(result_test+'.json')).read_text())
    report['library']=library
    (ROOT/'reports'/(report_name+'.json')).write_text(json.dumps(report,indent=2))
    errors=re.search(r'(?m)^(?:SCRIPT ERROR|ERROR:|FAIL |WARNING: ObjectDB instances leaked)',log)
    raise SystemExit(1 if run.returncode or report['failures'] or errors else 0)
