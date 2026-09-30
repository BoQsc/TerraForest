"""Reject native importer LODs that change independent terrain region boundaries."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot',required=True,type=Path)
args=parser.parse_args()

from terrain_probe_geometry import inspect

source=ROOT/'.build/tetra_probe'
names=[]
for site,x,z in [(0,960,960),(1,1280,1280),(2,1280,1280)]:
    names.append(f'{site}_{x}_{z}_32')
    names.extend(f'{site}_{x+dx}_{z+dz}_16' for dz in [0,16] for dx in [0,16])
for name in names:
    if not (source/(name+'.bin')).exists(): raise SystemExit('Run python tools/probe_terrain_tetra.py first')
with tempfile.TemporaryDirectory(prefix='lod_probe_',dir=ROOT/'.build') as tmp:
    project=Path(tmp)
    (project/'input').mkdir();(project/'output').mkdir();(project/'tests').mkdir()
    for name in names: shutil.copy2(source/(name+'.bin'),project/'input'/(name+'.bin'))
    shutil.copy2(ROOT/'tests/terrain_lod_probe.gd',project/'tests/terrain_lod_probe.gd')
    (project/'inputs.json').write_text(json.dumps(names))
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Terrain LOD decision probe"\n')
    run=subprocess.run([str(args.godot),'--headless','--path',str(project),'--script','res://tests/terrain_lod_probe.gd'],capture_output=True,text=True,timeout=60)
    log=run.stdout+'\n'+run.stderr
    (ROOT/'reports/terrain_lod_probe.log').write_text(log)
    if run.returncode or re.search(r'(?m)^(SCRIPT ERROR|ERROR:)',log): raise RuntimeError(log)
    report=json.loads((project/'output/report.json').read_text())
    failures=0
    for row in report['rows']:
        boundary,triangles,topology=inspect(project/'input'/(row['name']+'.bin'))
        row['input_topology']=topology
        row['input_sha256']=hashlib.sha256((project/'input'/(row['name']+'.bin')).read_bytes()).hexdigest()
        row['input_triangles']=sum(triangles.values())
        for level in row['levels']:
            after,faces,after_topology=inspect(project/'output'/level['file'])
            level['topology']=after_topology
            level['topology_counts_preserved']=after_topology==topology
            level['boundary_preserved']=after==boundary
            level['boundary_edges_removed']=sum((boundary-after).values())
            level['boundary_edges_added']=sum((after-boundary).values())
            removed_y=[struct.unpack('<3f',p)[1] for edge in (boundary-after) for p in edge]
            level['removed_boundary_y_range']=[min(removed_y),max(removed_y)] if removed_y else []
            level['sha256']=hashlib.sha256((project/'output'/level['file']).read_bytes()).hexdigest()
            if level['level']==-1:
                level['base_preserved']=faces==triangles
                failures+=not level['base_preserved']
            else: failures+=not(level['boundary_preserved'] and level['topology_counts_preserved'])
        failures+=len(row['levels'])<2
        row['eligible_levels']=[level['level'] for level in row['levels'] if level['level']>=0 and level['boundary_preserved'] and level['topology_counts_preserved']]
        print(row['name'], 'ms',round(row['generate_ms'],2), 'triangles',row['input_triangles'],'->',[level['triangles'] for level in row['levels'][1:]],'boundary',[level['boundary_preserved'] for level in row['levels'][1:]])
    report.update(failures=failures,adoption_qualified=False,
                  scope='Native ImporterMesh generation without material attributes. Exact edge-multiset preservation is a conservative independent-region contract; failure is not proof of a visible crack for every camera/LOD combination. Engine LOD size is not an independently verified geometric error bound.',
                  source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'tests/terrain_lod_probe.gd',Path(__file__).resolve()]})
    (ROOT/'reports/terrain_lod_probe.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Boundary/admission failures:',failures)
    raise SystemExit(bool(failures))
