"""Reject mixed-size geometric seams and measure local replacement amplification."""
from collections import Counter
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
import shutil
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
args = parser.parse_args()

def triangles(data):
    assert struct.unpack_from('<III', data) == (0x32505254, 1, 0)
    mesh = memoryview(data)[16:]
    magic, version, x, z, size, step, nv, ni, nf = struct.unpack_from('<9I', mesh)
    assert magic == 0x324d5254 and version == 5 and len(mesh) == 36+56*nv+4*ni+12*nf
    points = [bytes(mesh[36+12*i:48+12*i]) for i in range(nv)]
    indices = struct.unpack_from('<'+str(ni)+'I', mesh, 36+56*nv)
    result = Counter()
    for i in range(0, ni, 3):
        a,b,c = (points[j] for j in indices[i:i+3])
        result[min((a,b,c),(b,c,a),(c,a,b))] += 1
    return result

def edges(mesh):
    result = Counter()
    for (a,b,c), count in mesh.items():
        for u,v in [(a,b),(b,c),(c,a)]:
            result[tuple(sorted((u,v)))] += count
    return result

def boundary(mesh):
    return Counter({edge: count for edge,count in edges(mesh).items() if count==1})

checks = []
def check(name, passed, **details):
    checks.append(dict(name=name, passed=bool(passed), **details))
    print(('PASS ' if passed else 'FAIL ')+name)

begin = time.perf_counter()
source = ROOT/'addons/volumetric_terrain'
library = source/'bin/terrain_core.windows.template_release.x86_64.dll'
with tempfile.TemporaryDirectory(prefix='mixed_cut_', dir=ROOT/'.build') as temporary:
    project = Path(temporary)
    addon = project/'addons/volumetric_terrain'
    (addon/'bin').mkdir(parents=True)
    shutil.copy2(library, addon/'bin'/library.name)
    (addon/'terrain_core.gdextension').write_text((source/'terrain_core.gdextension').read_text().replace('terrain_core.windows.x86_64.dll',library.name))
    shutil.copy2(source/'mesh_codec.gd', addon/'mesh_codec.gd')
    (project/'tests').mkdir()
    shutil.copy2(ROOT/'tests/terrain_mixed_cut_probe.gd', project/'tests/terrain_mixed_cut_probe.gd')
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Mixed cut geometry probe"\n')
    result = subprocess.run([args.godot,'--headless','--path',str(project),'--script','res://tests/terrain_mixed_cut_probe.gd'],capture_output=True,text=True,timeout=60)
    log = result.stdout+'\n'+result.stderr
    (ROOT/'reports/terrain_mixed_cut_probe.log').write_text(log)
    if result.returncode or re.search(r'(?m)^(SCRIPT ERROR|ERROR:)',log): raise RuntimeError(log)
    raw = json.loads((project/'reports/terrain_mixed_cut_probe.json').read_text())
    check('native requests and edits succeed',raw['failures']==0)
    summaries = []
    for site in ['mountain','cave']:
        rows = [r for r in raw['rows'] if r['site']==site]
        all_meshes = {(r['phase'],tuple(r['request'])):triangles((project/'reports'/r['file']).read_bytes()) for r in rows}
        meshes = {k:v for k,v in all_meshes.items() if k[0] in ['before','after']}
        combined = {}
        for phase in ['before','after']:
            parent = next(m for (p,q),m in meshes.items() if p==phase and q[2]==256)
            cut = Counter()
            for (p,q),m in meshes.items():
                if p==phase and q[2]<256: cut.update(m)
            combined[phase] = cut
            extra = boundary(cut)-boundary(parent)
            missing = boundary(parent)-boundary(cut)
            check(f'{site} {phase} mixed cut has only parent open edges',not extra and not missing,extra_edges=len(extra),missing_edges=len(missing))
            duplicates = [(tri,n) for tri,n in cut.items() if n>1]
            check(f'{site} {phase} no duplicate triangles',not duplicates,duplicate_count=len(duplicates),examples=[dict(vertices=[struct.unpack('<3f',v) for v in tri],count=n) for tri,n in duplicates[:4]])
            bad_edges = [(edge,n) for edge,n in edges(cut).items() if n>2]
            check(f'{site} {phase} no overused geometric edges',not bad_edges,overused_edges=len(bad_edges),examples=[dict(vertices=[struct.unpack('<3f',v) for v in edge],count=n) for edge,n in bad_edges[:4]])
        replacement = Counter()
        for (phase,q),m in meshes.items():
            if q[2]==256: continue
            if phase==('after' if q[2]==16 else 'before'): replacement.update(m)
        changed_neighbors = []
        for (phase,q),m in meshes.items():
            if phase!='before' or q[2] in [16,256]: continue
            fresh = meshes['after',q]
            if m!=fresh:
                changed_neighbors.append(dict(request=q,removed=sum((m-fresh).values()),added=sum((fresh-m).values())))
        check(f'{site} replacing only four fine owners equals freshly rebuilt mixed cut',replacement==combined['after'],missing_triangles=sum((combined['after']-replacement).values()),extra_triangles=sum((replacement-combined['after']).values()),changed_coarse_neighbors=changed_neighbors)
        for (phase,q),m in all_meshes.items():
            if phase=='fine_before':
                fresh = all_meshes['fine_after',q]
                check(f'{site} full-resolution neighbor {q[:2]} unchanged',m==fresh,removed=sum((m-fresh).values()),added=sum((fresh-m).values()))
        # Conservative XZ projection of edit pages, neighboring pin pages and
        # extraction halo. This deliberately ignores Y and is a probe, not a
        # verified universal dependency bound or runtime policy.
        bounds = raw['edit_bounds'][site]
        low = [math.floor(bounds['lo'][i]/16)*16-18 for i in [0,2]]
        high = [(math.floor(bounds['hi'][i]/16)+2)*16+2 for i in [0,2]]
        selected = {q for phase,q in meshes if phase=='after' and q[2]<256 and
                    (q[2]==16 or (q[3]>1 and q[0]<=high[0] and q[0]+q[2]>=low[0] and q[1]<=high[1] and q[1]+q[2]>=low[1]))}
        expanded = Counter()
        for (phase,q),m in meshes.items():
            if q[2]<256 and phase==('after' if q in selected else 'before'): expanded.update(m)
        check(f'{site} page-expanded replacement equals fresh mixed cut',expanded==combined['after'],selected_owners=sorted(selected),projected_lo=low,projected_hi=high)
        after = [r for r in rows if r['phase']=='after']
        parent_row = next(r for r in after if r['request'][2]==256)
        fine_rows = [r for r in after if r['request'][2]==16]
        cut_rows = [r for r in after if r['request'][2]<256]
        expanded_ms = sum(r['native_ms'] for r in after if tuple(r['request']) in selected)
        check(f'{site} expanded native work fits whole-interaction rejection ceiling',expanded_ms<=150,native_ms=expanded_ms,ceiling_ms=150)
        parent_triangles = sum(meshes['after',tuple(parent_row['request'])].values())
        summaries.append(dict(site=site,owners=len(cut_rows),parent_triangles=parent_triangles,cut_triangles=sum(combined['after'].values()),triangle_ratio=sum(combined['after'].values())/parent_triangles,parent_bytes=parent_row['bytes'],cut_bytes=sum(r['bytes'] for r in cut_rows),parent_native_ms=parent_row['native_ms'],four_local_native_ms=sum(r['native_ms'] for r in fine_rows),expanded_owners=len(selected),expanded_native_ms=sum(r['native_ms'] for r in after if tuple(r['request']) in selected),initial_cut_native_ms=sum(r['native_ms'] for r in cut_rows)))
    report = dict(failures=sum(not c['passed'] for c in checks),adoption_qualified=False,checks=checks,summary=summaries,edit_bounds=raw['edit_bounds'],native_samples=raw['rows'],elapsed_seconds=time.perf_counter()-begin,mesh_hashes={r['file']:hashlib.sha256((project/'reports'/r['file']).read_bytes()).hexdigest() for r in raw['rows']},source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(),ROOT/'tests/terrain_mixed_cut_probe.gd',source/'mesh_codec.gd',library]},scope='Exact float-position render triangle multisets and open-edge comparison. Existing mesher; fixed mixed-size partitions, two sites, one excavation each. Expanded dependency bounds are conservative experimental XZ projections, not universally verified. No shading/material continuity, interpolation error, full manifold proof, live coverage transition, GPU, physics or endurance qualification.')
    (ROOT/'reports/terrain_mixed_cut_probe.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(summaries,indent=2))
    raise SystemExit(bool(report['failures']))
