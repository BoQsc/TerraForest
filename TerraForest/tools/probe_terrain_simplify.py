"""Test explicit native LOD controls and independently sampled surface distance."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import os
import subprocess
from bootstrap_native import ROOT,CACHE,bootstrap
from terrain_probe_geometry import inspect

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--admission',action='store_true',help='Exercise bounded coverage checks, retries and exact fallback')
args=parser.parse_args()

vendor=ROOT/'tests/native/vendor/meshoptimizer'
manifest=json.loads((vendor/'manifest.json').read_text())
for name,digest in manifest['files'].items():
    assert hashlib.sha256((vendor/name).read_bytes()).hexdigest()==digest, name
info=bootstrap()
folder=ROOT/'.build'/('admission_probe' if args.admission else 'simplify_probe')
folder.mkdir(exist_ok=True)
exe=folder/'probe.exe'
source=ROOT/'tests/native'/('terrain_admission_probe.cpp' if args.admission else 'terrain_simplify_probe.cpp')
env=os.environ.copy()
env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache')
env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
command=[info['zig'],'c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-fno-exceptions','-fno-sanitize=undefined','-ffp-contract=off','-I',str(vendor),str(source),*[str(vendor/name) for name in ['simplifier.cpp','allocator.cpp','indexgenerator.cpp']],'-o',str(exe)]
subprocess.run(command,check=True,timeout=120,env=env)
baseline_path=ROOT/'docs/evidence/terrain_tetra/terrain_tetra_probe.json.gz'
baseline=json.loads(gzip.decompress(baseline_path.read_bytes()))
rows=[];failures=0
for check in baseline['checks']:
    if 'sha256' not in check: continue
    name=check['name'];path=ROOT/'.build/tetra_probe'/(name+'.bin')
    if not path.exists(): raise SystemExit('Run tools/probe_terrain_tetra.py first')
    assert hashlib.sha256(path.read_bytes()).hexdigest()==check['sha256'],name
    boundary,triangles,topology=inspect(path)
    result=subprocess.run([str(exe),str(path),str(folder/name)],capture_output=True,text=True,check=True,timeout=60)
    levels=[]
    for line in result.stdout.splitlines():
        level=json.loads(line)
        output=folder/(name+'_'+str(level['level'])+'.bin')
        after,_,new_topology=inspect(output)
        level['boundary_preserved']=boundary==after
        level['topology_counts_preserved']=topology==new_topology
        level['topology']=new_topology
        level['sampled_error_pass']=max(level['sampled_forward'],level['sampled_reverse'])<=level['requested_error']+0.0005
        level['passed']=level['boundary_preserved'] and level['topology_counts_preserved'] and level['sampled_error_pass']
        if args.admission:
            level['coverage_pass']=level['coverage_upper']<=level['requested_error'] and level['coverage_queries']<=200000 and level['attempts']<=3
            level['fallback_exact']=not level['fallback'] or output.read_bytes()==path.read_bytes()
            level['passed']=level['passed'] and level['coverage_pass'] and level['fallback_exact']
        level['sha256']=hashlib.sha256(output.read_bytes()).hexdigest()
        failures+=not level['passed'];levels.append(level)
    assert len(levels)==(2 if args.admission else 4)
    rows.append(dict(name=name,input_sha256=check['sha256'],input_triangles=sum(triangles.values()),input_topology=topology,levels=levels))
    print(name,[(r['triangles'],round(r['simplify_ms'],2),r['boundary_preserved'],r['topology_counts_preserved'],r['sampled_error_pass']) for r in levels])
report=dict(failures=failures,adoption_qualified=False,rows=rows,build_command=command,toolchain_lock_sha256=info['lock_sha256'],vendor=manifest,
            source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,ROOT/'tests/native/terrain_distance_probe.hpp',Path(__file__).resolve(),ROOT/'tools/terrain_probe_geometry.py']},
            scope='Position-only simplification from original meshes at each error setting. Border lock and absolute error enabled; component pruning disabled. Symmetric distances sample all used vertices and triangle centroids, not a continuous Hausdorff bound. 0.0005 world-unit numerical allowance. No normals/material/error-to-density-field or GPU qualification.')
if args.admission:
    report['scope']='Bounded admission prototype: three simplification attempts, 200000 coverage cells total and depth 20; exact-original fallback. Coverage uses distances of subtriangle vertices to one common target triangle, in both directions, in double precision with 1e-7 numerical reserve. Not interval arithmetic or formal floating-point certification. Distance is against the candidate input, not the original field. Runtime budgets, materials and GPU remain unqualified.'
    levels=[level for row in rows for level in row['levels']]
    report['admission_summary']={
        'outputs':len(levels),
        'exact_fallbacks':sum(level['fallback'] for level in levels),
        'accepted_reductions':sum(not level['fallback'] for level in levels),
        'coverage_exhaustions':sum(level['coverage_exhausted'] for level in levels),
        'max_admission_ms':max(level['admission_ms'] for level in levels),
        'min_admission_ms':min(level['admission_ms'] for level in levels),
        # Necessary ceiling only: the full interaction also needs extraction,
        # queueing, publication and collision. Passing this does not qualify it.
        'whole_interaction_ceiling_ms':150,
        'outputs_exceeding_whole_interaction_ceiling':sum(level['admission_ms']>150 for level in levels),
    }
    report['live_edit_candidate_rejected']=bool(report['admission_summary']['outputs_exceeding_whole_interaction_ceiling'])
    print('Admission evidence:',report['admission_summary'])
(ROOT/'reports'/('terrain_admission_probe.json' if args.admission else 'terrain_simplify_probe.json')).write_text(json.dumps(report,indent=2)+'\n')
print('Geometry gate failures:',failures)
raise SystemExit(bool(failures or report.get('live_edit_candidate_rejected',False)))
