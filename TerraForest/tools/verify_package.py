"""Verify archived hashes and run integration from a clean extraction with no editor cache."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import zipfile

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--archive',type=Path,default=root/'dist/TerraForest-source.zip')
p.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
args=p.parse_args()
if not args.godot:p.error('Specify --godot PATH')
engine=Path(args.godot)
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():engine=direct
build=root/'.build'
build.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='package_',dir=build) as temporary:
    project=Path(temporary).resolve()
    assert build.resolve() in project.parents
    with zipfile.ZipFile(args.archive) as archive:
        for name in archive.namelist():
            target=(project/name).resolve()
            if project not in target.parents:
                raise ValueError('Archive member escapes extraction directory')
        archive.extractall(project)
    manifest=json.loads((project/'MANIFEST.sha256.json').read_text(encoding='utf-8'))
    for name,expected in manifest.items():
        target=(project/name).resolve()
        if project not in target.parents or hashlib.sha256(target.read_bytes()).hexdigest()!=expected:
            raise ValueError('Manifest mismatch: '+name)
    assert not (project/'.godot').exists()
    run=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/integration.gd'],capture_output=True,text=True,timeout=180)
    log=run.stdout+'\n'+run.stderr
    report=json.loads((project/'reports/integration.json').read_text())
    ok=run.returncode==0 and report['failures']==0 and 'ERROR:' not in log and 'instances leaked' not in log
    planner=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/terrain_planner.gd'],capture_output=True,text=True,timeout=120)
    planner_log=planner.stdout+'\n'+planner.stderr
    planner_report=json.loads((project/'reports/terrain_planner.json').read_text())
    ok=ok and planner.returncode==0 and planner_report['failures']==0 and 'ERROR:' not in planner_log and 'instances leaked' not in planner_log
    collision=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/terrain_collision.gd'],capture_output=True,text=True,timeout=120)
    collision_log=collision.stdout+'\n'+collision.stderr
    collision_report=json.loads((project/'reports/terrain_collision.json').read_text())
    ok=ok and collision.returncode==0 and collision_report['failures']==0 and 'ERROR:' not in collision_log and 'instances leaked' not in collision_log
    lattice=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_lattice.gd'],capture_output=True,text=True,timeout=120)
    lattice_log=lattice.stdout+'\n'+lattice.stderr
    lattice_report=json.loads((project/'reports/block_lattice.json').read_text())
    ok=ok and lattice.returncode==0 and lattice_report['failures']==0 and 'ERROR:' not in lattice_log and 'instances leaked' not in lattice_log
    worker=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_worker.gd'],capture_output=True,text=True,timeout=120)
    worker_log=worker.stdout+'\n'+worker.stderr
    worker_report=json.loads((project/'reports/block_worker.json').read_text())
    ok=ok and worker.returncode==0 and worker_report['failures']==0 and 'ERROR:' not in worker_log and 'instances leaked' not in worker_log
    building_collision=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/building_collision_stream.gd'],capture_output=True,text=True,timeout=120)
    building_collision_log=building_collision.stdout+'\n'+building_collision.stderr
    building_collision_report=json.loads((project/'reports/building_collision_stream.json').read_text())
    ok=ok and building_collision.returncode==0 and building_collision_report['failures']==0 and 'ERROR:' not in building_collision_log and 'instances leaked' not in building_collision_log
    structures=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/structures.gd'],capture_output=True,text=True,timeout=120)
    structure_log=structures.stdout+'\n'+structures.stderr
    structure_report=json.loads((project/'reports/structures.json').read_text())
    ok=ok and structures.returncode==0 and structure_report['failures']==0 and 'ERROR:' not in structure_log and 'instances leaked' not in structure_log
    placements=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/static_placements.gd'],capture_output=True,text=True,timeout=120)
    placement_log=placements.stdout+'\n'+placements.stderr
    placement_report=json.loads((project/'reports/static_placements.json').read_text())
    ok=ok and placements.returncode==0 and placement_report['failures']==0 and 'ERROR:' not in placement_log and 'instances leaked' not in placement_log
    persistence=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/structure_persistence.gd'],capture_output=True,text=True,timeout=120)
    persistence_log=persistence.stdout+'\n'+persistence.stderr
    persistence_report=json.loads((project/'reports/structure_persistence.json').read_text())
    ok=ok and persistence.returncode==0 and persistence_report['failures']==0 and '\nERROR:' not in persistence_log and 'SCRIPT ERROR:' not in persistence_log and 'instances leaked' not in persistence_log
    scene=subprocess.run([str(engine),'--headless','--path',str(project),'--quit-after','120','res://demo/structures.tscn'],capture_output=True,text=True,timeout=60)
    scene_log=scene.stdout+'\n'+scene.stderr
    ok=ok and scene.returncode==0 and 'ERROR:' not in scene_log and 'instances leaked' not in scene_log
    log+='\n'+planner_log+'\n'+collision_log+'\n'+lattice_log+'\n'+worker_log+'\n'+building_collision_log+'\n'+structure_log+'\n'+placement_log+'\n'+persistence_log+'\n'+scene_log
    (root/'reports').mkdir(exist_ok=True)
    (root/'reports/package_verification.json').write_text(json.dumps({'archive':args.archive.name,'sha256':hashlib.sha256(args.archive.read_bytes()).hexdigest(),'manifest_files':len(manifest),'checks':len(report['checks']),'terrain_planner_checks':planner_report['checks'],'terrain_collision_checks':collision_report['checks'],'block_lattice_checks':lattice_report['checks'],'block_worker_checks':worker_report['checks'],'building_collision_checks':building_collision_report['checks'],'structures_checks':structure_report['checks'],'static_placement_checks':placement_report['checks'],'structure_persistence_checks':len(persistence_report['checks']),'structures_scene_smoke':scene.returncode==0 and 'ERROR:' not in scene_log,'pass':ok,'log':log},indent=2),encoding='utf-8')
    print(f'{"PASS" if ok else "FAIL"} {len(manifest)} archived hashes; {len(report["checks"])} integration + {planner_report["checks"]} terrain planner + {collision_report["checks"]} terrain collision + {lattice_report["checks"]} block lattice + {structure_report["checks"]} structures + {placement_report["checks"]} placement + {len(persistence_report["checks"])} structure persistence checks; construction scene startup')
    if not ok:print(log)
    raise SystemExit(0 if ok else 1)
