"""Diagnose frozen candidate collision misses without changing their geometry baseline."""
from pathlib import Path
from collections import defaultdict
import argparse,gzip,hashlib,json,re,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--godot',required=True);args=parser.parse_args()
baseline=ROOT/'docs/evidence/terrain_candidate_collision/terrain_candidate_collision.json.gz'
data=json.loads(gzip.decompress(baseline.read_bytes()))
missed=[r for r in data['rays'] if not r['hit']]
assert len(missed)==21
library=ROOT/'addons/volumetric_terrain/bin/terrain_core.windows.template_release.x86_64.dll'
script=ROOT/'tests/terrain_collision_isolation_probe.gd'
with tempfile.TemporaryDirectory(prefix='collision_isolation_',dir=ROOT/'.build') as temporary:
    project=Path(temporary);addon=project/'addons/volumetric_terrain';(addon/'bin').mkdir(parents=True)
    shutil.copy2(library,addon/'bin'/library.name);shutil.copy2(script,project/'probe.gd')
    (addon/'terrain_core.gdextension').write_text('[configuration]\nentry_symbol="terrain_library_init"\ncompatibility_minimum="4.7"\n[libraries]\nwindows.debug.x86_64="res://addons/volumetric_terrain/bin/'+library.name+'"\nwindows.release.x86_64="res://addons/volumetric_terrain/bin/'+library.name+'"\n')
    (project/'input.json').write_text(json.dumps(missed));(project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Collision isolation"\n')
    run=subprocess.run([args.godot,'--headless','--path',str(project),'--script','res://probe.gd'],capture_output=True,text=True,timeout=120)
    log=run.stdout+'\n'+run.stderr;(ROOT/'reports/terrain_collision_isolation.log').write_text(log,encoding='utf-8');print(log)
    if run.returncode or re.search(r'(?m)^(SCRIPT ERROR|ERROR:|WARNING: ObjectDB instances leaked)',log):raise SystemExit(1)
    report=json.loads((project/'reports/isolation.json').read_text());assert len(report['results'])==756
    grouped=defaultdict(lambda:dict(cases=0,physics_hits=0,geometry_ray_hits=0,geometry_unit_ray_hits=0))
    for r in report['results']:
        group=grouped[f"{r['mode']} scale {r['scale']} reach {r['ray_half_length']}"];group['cases']+=1;group['physics_hits']+=r['physics_hit'];group['geometry_ray_hits']+=r['geometry_ray_hit'];group['geometry_unit_ray_hits']+=r['geometry_unit_ray_hit']
    report.update(groups=dict(grouped),baseline_sha256=hashlib.sha256(baseline.read_bytes()).hexdigest(),source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [script,library,Path(__file__).resolve()]},adoption_qualified=False)
    (ROOT/'reports/terrain_collision_isolation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report['groups'],indent=2))
