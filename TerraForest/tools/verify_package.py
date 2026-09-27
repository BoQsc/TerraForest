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
    structures=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/structures.gd'],capture_output=True,text=True,timeout=120)
    structure_log=structures.stdout+'\n'+structures.stderr
    structure_report=json.loads((project/'reports/structures.json').read_text())
    ok=ok and structures.returncode==0 and structure_report['failures']==0 and 'ERROR:' not in structure_log and 'instances leaked' not in structure_log
    placements=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/static_placements.gd'],capture_output=True,text=True,timeout=120)
    placement_log=placements.stdout+'\n'+placements.stderr
    placement_report=json.loads((project/'reports/static_placements.json').read_text())
    ok=ok and placements.returncode==0 and placement_report['failures']==0 and 'ERROR:' not in placement_log and 'instances leaked' not in placement_log
    scene=subprocess.run([str(engine),'--headless','--path',str(project),'--quit-after','120','res://demo/structures.tscn'],capture_output=True,text=True,timeout=60)
    scene_log=scene.stdout+'\n'+scene.stderr
    ok=ok and scene.returncode==0 and 'ERROR:' not in scene_log and 'instances leaked' not in scene_log
    log+='\n'+structure_log+'\n'+placement_log+'\n'+scene_log
    (root/'reports').mkdir(exist_ok=True)
    (root/'reports/package_verification.json').write_text(json.dumps({'archive':args.archive.name,'sha256':hashlib.sha256(args.archive.read_bytes()).hexdigest(),'manifest_files':len(manifest),'checks':len(report['checks']),'structures_checks':structure_report['checks'],'static_placement_checks':placement_report['checks'],'structures_scene_smoke':scene.returncode==0 and 'ERROR:' not in scene_log,'pass':ok,'log':log},indent=2),encoding='utf-8')
    print(f'{"PASS" if ok else "FAIL"} {len(manifest)} archived hashes; {len(report["checks"])} integration + {structure_report["checks"]} structures + {placement_report["checks"]} static placement checks; construction scene startup')
    if not ok:print(log)
    raise SystemExit(0 if ok else 1)
