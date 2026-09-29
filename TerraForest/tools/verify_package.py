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
    readiness=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/building_readiness.gd'],capture_output=True,text=True,timeout=120)
    readiness_log=readiness.stdout+'\n'+readiness.stderr
    readiness_report=json.loads((project/'reports/building_readiness.json').read_text())
    ok=ok and readiness.returncode==0 and readiness_report['failures']==0 and 'ERROR:' not in readiness_log and 'instances leaked' not in readiness_log
    structures=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/structures.gd'],capture_output=True,text=True,timeout=120)
    structure_log=structures.stdout+'\n'+structures.stderr
    structure_report=json.loads((project/'reports/structures.json').read_text())
    ok=ok and structures.returncode==0 and structure_report['failures']==0 and 'ERROR:' not in structure_log and 'instances leaked' not in structure_log
    regions=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_regions.gd'],capture_output=True,text=True,timeout=120)
    region_log=regions.stdout+'\n'+regions.stderr
    region_report=json.loads((project/'reports/block_regions.json').read_text())
    ok=ok and regions.returncode==0 and region_report['failures']==0 and 'ERROR:' not in region_log and 'instances leaked' not in region_log
    region_store=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_region_store.gd'],capture_output=True,text=True,timeout=180)
    region_store_log=region_store.stdout+'\n'+region_store.stderr
    region_store_report=json.loads((project/'reports/block_region_store.json').read_text())
    ok=ok and region_store.returncode==0 and region_store_report['failures']==0 and 'ERROR:' not in region_store_log and 'instances leaked' not in region_store_log
    region_io=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_region_io.gd'],capture_output=True,text=True,timeout=180)
    region_io_log=region_io.stdout+'\n'+region_io.stderr
    region_io_report=json.loads((project/'reports/block_region_io.json').read_text())
    ok=ok and region_io.returncode==0 and region_io_report['failures']==0 and 'ERROR:' not in region_io_log and 'instances leaked' not in region_io_log
    checkpoints=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_region_checkpoints.gd'],capture_output=True,text=True,timeout=180)
    checkpoint_log=checkpoints.stdout+'\n'+checkpoints.stderr
    checkpoint_report=json.loads((project/'reports/block_region_checkpoints.json').read_text())
    ok=ok and checkpoints.returncode==0 and checkpoint_report['failures']==0 and 'ERROR:' not in checkpoint_log and 'instances leaked' not in checkpoint_log
    bootstrap=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_region_bootstrap.gd'],capture_output=True,text=True,timeout=120)
    bootstrap_log=bootstrap.stdout+'\n'+bootstrap.stderr
    bootstrap_report=json.loads((project/'reports/block_region_bootstrap.json').read_text())
    ok=ok and bootstrap.returncode==0 and bootstrap_report['failures']==0 and 'ERROR:' not in bootstrap_log and 'instances leaked' not in bootstrap_log
    partial=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/partial_region_storage.gd'],capture_output=True,text=True,timeout=120)
    partial_log=partial.stdout+'\n'+partial.stderr
    partial_report=json.loads((project/'reports/partial_region_storage.json').read_text())
    ok=ok and partial.returncode==0 and partial_report['failures']==0 and 'ERROR:' not in partial_log and 'instances leaked' not in partial_log
    metadata=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/region_metadata.gd'],capture_output=True,text=True,timeout=180)
    metadata_log=metadata.stdout+'\n'+metadata.stderr
    metadata_report=json.loads((project/'reports/region_metadata.json').read_text())
    ok=ok and metadata.returncode==0 and metadata_report['failures']==0 and '\nERROR:' not in metadata_log and 'SCRIPT ERROR:' not in metadata_log and 'instances leaked' not in metadata_log
    archive_reads=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/region_archive_reads.gd'],capture_output=True,text=True,timeout=180)
    archive_reads_log=archive_reads.stdout+'\n'+archive_reads.stderr
    archive_reads_report=json.loads((project/'reports/region_archive_reads.json').read_text())
    ok=ok and archive_reads.returncode==0 and archive_reads_report['failures']==0 and 'ERROR:' not in archive_reads_log and 'instances leaked' not in archive_reads_log
    block_pager=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_pager.gd'],capture_output=True,text=True,timeout=120)
    block_pager_log=block_pager.stdout+'\n'+block_pager.stderr
    block_pager_report=json.loads((project/'reports/block_pager.json').read_text())
    ok=ok and block_pager.returncode==0 and block_pager_report['failures']==0 and 'ERROR:' not in block_pager_log and 'instances leaked' not in block_pager_log
    pager_stress=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_pager_stress.gd'],capture_output=True,text=True,timeout=180)
    pager_stress_log=pager_stress.stdout+'\n'+pager_stress.stderr
    pager_stress_report=json.loads((project/'reports/block_pager_stress.json').read_text())
    ok=ok and pager_stress.returncode==0 and pager_stress_report['failures']==0 and 'ERROR:' not in pager_stress_log and 'instances leaked' not in pager_stress_log
    block_pager_world=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/block_pager_world.gd'],capture_output=True,text=True,timeout=300)
    block_pager_world_log=block_pager_world.stdout+'\n'+block_pager_world.stderr
    block_pager_world_report=json.loads((project/'reports/block_pager_world.json').read_text())
    ok=ok and block_pager_world.returncode==0 and block_pager_world_report['failures']==0 and 'ERROR:' not in block_pager_world_log and 'instances leaked' not in block_pager_world_log
    placements=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/static_placements.gd'],capture_output=True,text=True,timeout=120)
    placement_log=placements.stdout+'\n'+placements.stderr
    placement_report=json.loads((project/'reports/static_placements.json').read_text())
    ok=ok and placements.returncode==0 and placement_report['failures']==0 and 'ERROR:' not in placement_log and 'instances leaked' not in placement_log
    persistence=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/structure_persistence.gd'],capture_output=True,text=True,timeout=120)
    persistence_log=persistence.stdout+'\n'+persistence.stderr
    persistence_report=json.loads((project/'reports/structure_persistence.json').read_text())
    ok=ok and persistence.returncode==0 and persistence_report['failures']==0 and '\nERROR:' not in persistence_log and 'SCRIPT ERROR:' not in persistence_log and 'instances leaked' not in persistence_log
    region_archive=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/region_world_archive.gd'],capture_output=True,text=True,timeout=120)
    region_archive_log=region_archive.stdout+'\n'+region_archive.stderr
    region_archive_report=json.loads((project/'reports/region_world_archive.json').read_text())
    ok=ok and region_archive.returncode==0 and region_archive_report['failures']==0 and 'ERROR:' not in region_archive_log and 'instances leaked' not in region_archive_log
    region_persistence=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://tests/structure_persistence.gd','--','--region-storage'],capture_output=True,text=True,timeout=180)
    region_persistence_log=region_persistence.stdout+'\n'+region_persistence.stderr
    region_persistence_report=json.loads((project/'reports/structure_region_persistence.json').read_text())
    ok=ok and region_persistence.returncode==0 and region_persistence_report['failures']==0 and '\nERROR:' not in region_persistence_log and 'SCRIPT ERROR:' not in region_persistence_log and 'instances leaked' not in region_persistence_log
    scene=subprocess.run([str(engine),'--headless','--path',str(project),'--quit-after','120','res://demo/structures.tscn'],capture_output=True,text=True,timeout=60)
    scene_log=scene.stdout+'\n'+scene.stderr
    ok=ok and scene.returncode==0 and 'ERROR:' not in scene_log and 'instances leaked' not in scene_log
    log+='\n'+planner_log+'\n'+collision_log+'\n'+lattice_log+'\n'+worker_log+'\n'+building_collision_log+'\n'+readiness_log+'\n'+structure_log+'\n'+region_log+'\n'+region_store_log+'\n'+region_io_log+'\n'+checkpoint_log+'\n'+bootstrap_log+'\n'+partial_log+'\n'+metadata_log+'\n'+archive_reads_log+'\n'+block_pager_log+'\n'+pager_stress_log+'\n'+block_pager_world_log+'\n'+placement_log+'\n'+persistence_log+'\n'+region_archive_log+'\n'+region_persistence_log+'\n'+scene_log
    (root/'reports').mkdir(exist_ok=True)
    (root/'reports/package_verification.json').write_text(json.dumps({'archive':args.archive.name,'sha256':hashlib.sha256(args.archive.read_bytes()).hexdigest(),'manifest_files':len(manifest),'checks':len(report['checks']),'terrain_planner_checks':planner_report['checks'],'terrain_collision_checks':collision_report['checks'],'block_lattice_checks':lattice_report['checks'],'block_worker_checks':worker_report['checks'],'building_collision_checks':building_collision_report['checks'],'building_readiness_checks':readiness_report['checks'],'structures_checks':structure_report['checks'],'block_region_checks':region_report['checks'],'block_region_store_checks':region_store_report['checks'],'block_region_io_checks':region_io_report['checks'],'block_checkpoint_checks':checkpoint_report['checks'],'block_bootstrap_checks':bootstrap_report['checks'],'partial_storage_checks':partial_report['checks'],'region_metadata_checks':metadata_report['checks'],'archive_read_checks':archive_reads_report['checks'],'block_pager_checks':block_pager_report['checks'],'pager_stress_checks':pager_stress_report['checks'],'block_pager_world_checks':block_pager_world_report['checks'],'static_placement_checks':placement_report['checks'],'structure_persistence_checks':len(persistence_report['checks']),'region_archive_checks':region_archive_report['checks'],'region_persistence_checks':len(region_persistence_report['checks']),'structures_scene_smoke':scene.returncode==0 and 'ERROR:' not in scene_log,'pass':ok,'log':log},indent=2),encoding='utf-8')
    print(f'{"PASS" if ok else "FAIL"} {len(manifest)} archived hashes; {len(report["checks"])} integration + {planner_report["checks"]} terrain planner + {collision_report["checks"]} terrain collision + {lattice_report["checks"]} block lattice + {worker_report["checks"]} block worker + {building_collision_report["checks"]} building collision + {readiness_report["checks"]} building readiness + {region_report["checks"]} block region + {region_store_report["checks"]} region store + {region_io_report["checks"]} region I/O + {checkpoint_report["checks"]} checkpoint + {bootstrap_report["checks"]} bootstrap + {partial_report["checks"]} partial storage + {metadata_report["checks"]} metadata + {archive_reads_report["checks"]} archive reads + {block_pager_report["checks"]} pager + {pager_stress_report["checks"]} pager stress + {block_pager_world_report["checks"]} persistent paging + {structure_report["checks"]} structures + {placement_report["checks"]} placement + {len(persistence_report["checks"])} structure persistence + {region_archive_report["checks"]} region archive + {len(region_persistence_report["checks"])} region persistence checks; construction scene startup')
    if not ok:print(log)
    raise SystemExit(0 if ok else 1)
