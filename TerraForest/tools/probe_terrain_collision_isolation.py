"""Diagnose frozen candidate collision misses without changing their geometry baseline."""
from pathlib import Path
from collections import defaultdict
import argparse,gzip,hashlib,json,re,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--godot',required=True);parser.add_argument('--exact-zero',action='store_true');args=parser.parse_args()
baseline=ROOT/('docs/evidence/terrain_exact_zero/terrain_exact_zero_collision.json.gz' if args.exact_zero else 'docs/evidence/terrain_candidate_collision/terrain_candidate_collision.json.gz')
output='terrain_exact_zero_sweeps' if args.exact_zero else 'terrain_collision_sweeps'
data=json.loads(gzip.decompress(baseline.read_bytes()))
missed=[r for r in data['rays'] if not r['hit']]
assert len(missed)==(1 if args.exact_zero else 21)
library=ROOT/'addons/volumetric_terrain/bin/terrain_core.windows.template_release.x86_64.dll'
script=ROOT/'tests/terrain_collision_isolation_probe.gd'
with tempfile.TemporaryDirectory(prefix='collision_isolation_',dir=ROOT/'.build') as temporary:
    project=Path(temporary);addon=project/'addons/volumetric_terrain';(addon/'bin').mkdir(parents=True)
    shutil.copy2(library,addon/'bin'/library.name);shutil.copy2(script,project/'probe.gd')
    (addon/'terrain_core.gdextension').write_text('[configuration]\nentry_symbol="terrain_library_init"\ncompatibility_minimum="4.7"\n[libraries]\nwindows.debug.x86_64="res://addons/volumetric_terrain/bin/'+library.name+'"\nwindows.release.x86_64="res://addons/volumetric_terrain/bin/'+library.name+'"\n')
    (project/'input.json').write_text(json.dumps(missed));(project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Collision isolation"\n')
    run=subprocess.run([args.godot,'--headless','--path',str(project),'--script','res://probe.gd'],capture_output=True,text=True,timeout=120)
    log=run.stdout+'\n'+run.stderr;(ROOT/'reports'/(output+'.log')).write_text(log,encoding='utf-8');print(log)
    if run.returncode or re.search(r'(?m)^(SCRIPT ERROR|ERROR:|WARNING: ObjectDB instances leaked)',log):raise SystemExit(1)
    report=json.loads((project/'reports/isolation.json').read_text());assert len(report['results'])==len(missed)*36
    assert len(report['sweeps'])==len(missed)*48
    sweep_groups=defaultdict(lambda:dict(cases=0,hits=0))
    for r in report['sweeps']:
        group=sweep_groups[f"{r['mode']} scale {r['scale']} {r['shape']} displaced {r['displaced_control']}"]
        group['cases']+=1;group['hits']+=r['hit']
    report['sweep_failures']=sum(r['hit']==r['displaced_control'] or not 0<=r['safe_fraction']<=r['unsafe_fraction']<=1 for r in report['sweeps'])
    grouped=defaultdict(lambda:dict(cases=0,physics_hits=0,geometry_ray_hits=0,geometry_unit_ray_hits=0))
    for r in report['results']:
        group=grouped[f"{r['mode']} scale {r['scale']} reach {r['ray_half_length']}"];group['cases']+=1;group['physics_hits']+=r['physics_hit'];group['geometry_ray_hits']+=r['geometry_ray_hit'];group['geometry_unit_ray_hits']+=r['geometry_unit_ray_hit']
    report.update(sweep_groups=dict(sweep_groups),groups=dict(grouped),baseline_sha256=hashlib.sha256(baseline.read_bytes()).hexdigest(),source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [script,library,Path(__file__).resolve()]},adoption_qualified=False)
    (ROOT/'reports'/(output+'.json')).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(sweep_cases=len(report['sweeps']),centered_hits=sum(r['hit'] for r in report['sweeps'] if not r['displaced_control']),displaced_hits=sum(r['hit'] for r in report['sweeps'] if r['displaced_control']))))
    raise SystemExit(bool(report['sweep_failures']))
