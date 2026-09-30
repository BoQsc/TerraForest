"""Test explicit native LOD controls and independently sampled surface distance."""
from pathlib import Path
import gzip
import hashlib
import json
import os
import subprocess
from bootstrap_native import ROOT,CACHE,bootstrap
from terrain_probe_geometry import inspect

vendor=ROOT/'tests/native/vendor/meshoptimizer'
manifest=json.loads((vendor/'manifest.json').read_text())
for name,digest in manifest['files'].items():
    assert hashlib.sha256((vendor/name).read_bytes()).hexdigest()==digest, name
info=bootstrap()
folder=ROOT/'.build/simplify_probe'
folder.mkdir(exist_ok=True)
exe=folder/'probe.exe'
source=ROOT/'tests/native/terrain_simplify_probe.cpp'
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
        level['sha256']=hashlib.sha256(output.read_bytes()).hexdigest()
        failures+=not level['passed'];levels.append(level)
    assert len(levels)==4
    rows.append(dict(name=name,input_sha256=check['sha256'],input_triangles=sum(triangles.values()),input_topology=topology,levels=levels))
    print(name,[(r['triangles'],round(r['simplify_ms'],2),r['boundary_preserved'],r['topology_counts_preserved'],r['sampled_error_pass']) for r in levels])
report=dict(failures=failures,adoption_qualified=False,rows=rows,build_command=command,toolchain_lock_sha256=info['lock_sha256'],vendor=manifest,
            source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,Path(__file__).resolve(),ROOT/'tools/terrain_probe_geometry.py']},
            scope='Position-only simplification from original meshes at each error setting. Border lock and absolute error enabled; component pruning disabled. Symmetric distances sample all used vertices and triangle centroids, not a continuous Hausdorff bound. 0.0005 world-unit numerical allowance. No normals/material/error-to-density-field or GPU qualification.')
(ROOT/'reports/terrain_simplify_probe.json').write_text(json.dumps(report,indent=2)+'\n')
print('Rejected levels:',failures)
raise SystemExit(bool(failures))
