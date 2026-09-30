"""Cheap exact-position boundary and fine-partition rejection test; no runtime changes."""
from pathlib import Path
from collections import Counter
import argparse
import hashlib
import gzip
import json
import re
import shutil
import struct
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot',required=True,type=Path)
args=parser.parse_args()


def triangle(a,b,c):
    # Preserve winding but ignore the choice of first vertex. Raw float bytes
    # avoid tolerances hiding cracks; multisets expose duplicates and omissions.
    return min((a,b,c),(b,c,a),(c,a,b))


def decode(data):
    assert struct.unpack_from('<III',data)==(0x32505254,1,0)
    mesh=memoryview(data)[16:]
    magic,version,x,z,size,step,nv,ni,nf=struct.unpack_from('<9I',mesh)
    assert magic==0x324d5254 and version==5 and len(mesh)==36+56*nv+4*ni+12*nf
    points=[bytes(mesh[36+12*i:48+12*i]) for i in range(nv)]
    indices=struct.unpack_from('<'+str(ni)+'I',mesh,36+56*nv)
    triangles=Counter()
    edges=Counter()
    indexed_edges=Counter()
    cleaned_indexed_edges=Counter()
    degenerate=0
    for i in range(0,ni,3):
        a,b,c=(points[j] for j in indices[i:i+3])
        ia,ib,ic=indices[i:i+3]
        for u,v in [(ia,ib),(ib,ic),(ic,ia)]: indexed_edges[tuple(sorted((u,v)))]+=1
        triangles[triangle(a,b,c)]+=1
        if len({a,b,c})<3: degenerate+=1
        else:
            for u,v in [(ia,ib),(ib,ic),(ic,ia)]: cleaned_indexed_edges[tuple(sorted((u,v)))]+=1
        for u,v in [(a,b),(b,c),(c,a)]: edges[tuple(sorted((u,v)))]+=1
    faces=mesh[36+56*nv+4*ni:]
    collision=Counter(triangle(bytes(faces[i:i+12]),bytes(faces[i+12:i+24]),bytes(faces[i+24:i+36])) for i in range(0,len(faces),36))
    return dict(triangles=triangles,boundary=Counter({e:n for e,n in edges.items() if n==1}),
                nonmanifold=sum(n>2 for n in edges.values()),indexed_nonmanifold=sum(n>2 for n in indexed_edges.values()),degenerate=degenerate,
                after_removing_degenerate=sum(n>2 for n in cleaned_indexed_edges.values()),
                bad_edge_examples=[dict(a=struct.unpack('<3f',e[0]),b=struct.unpack('<3f',e[1]),incidence=n) for e,n in edges.items() if n>2][:4],
                indexed_bad_edge_examples=[dict(a=struct.unpack('<3f',points[e[0]]),b=struct.unpack('<3f',points[e[1]]),incidence=n) for e,n in indexed_edges.items() if n>2][:4],
                collision=collision,bytes=len(data),count=ni//3)


begin=time.perf_counter()
checks=[]
def check(name,ok,**details):
    checks.append(dict(name=name,passed=bool(ok),**details))
    print(('PASS ' if ok else 'FAIL ')+name)

(ROOT/'.build').mkdir(exist_ok=True)
(ROOT/'reports').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='boundary_probe_',dir=ROOT/'.build') as temporary:
    project=Path(temporary)
    addon=project/'addons/volumetric_terrain'
    (addon/'bin').mkdir(parents=True)
    source=ROOT/'addons/volumetric_terrain'
    library=source/'bin/terrain_core.windows.template_release.x86_64.dll'
    shutil.copy2(library,addon/'bin'/library.name)
    (addon/'terrain_core.gdextension').write_text((source/'terrain_core.gdextension').read_text().replace('terrain_core.windows.x86_64.dll',library.name))
    shutil.copy2(source/'mesh_codec.gd',addon/'mesh_codec.gd')
    (project/'tests').mkdir()
    shutil.copy2(ROOT/'tests/terrain_boundary_probe.gd',project/'tests/terrain_boundary_probe.gd')
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Boundary decision probe"\n')
    run=subprocess.run([str(args.godot),'--headless','--path',str(project),'--script','res://tests/terrain_boundary_probe.gd'],capture_output=True,text=True,timeout=60)
    log=run.stdout+'\n'+run.stderr
    (ROOT/'reports/terrain_boundary_probe.log').write_text(log)
    if run.returncode or re.search(r'(?m)^(SCRIPT ERROR|ERROR:)',log): raise RuntimeError(log)
    raw=json.loads((project/'reports/terrain_boundary_probe.json').read_text())
    failing_packet=(project/'reports/cave_960_960_32_1.bin').read_bytes()
    (ROOT/'reports/terrain_boundary_cave.bin.gz').write_bytes(gzip.compress(failing_packet,mtime=0))
    check('native requests and excavation succeed',raw['failures']==0)
    summary=[]
    for site in dict.fromkeys(r['site'] for r in raw['rows']):
        rows=[r for r in raw['rows'] if r['site']==site]
        meshes={tuple(r['request']):decode((project/'reports'/r['file']).read_bytes()) for r in rows}
        parent=next(m for q,m in meshes.items() if q[2]==64)
        children={q:m for q,m in meshes.items() if q[2]==32 and q[3]==1}
        combined=Counter()
        collision=Counter()
        for m in children.values():
            combined.update(m['triangles'])
            collision.update(m['collision'])
        check(site+' exact fine partition',combined==parent['triangles'],missing=sum((parent['triangles']-combined).values()),extra=sum((combined-parent['triangles']).values()))
        # 64 m packets intentionally omit collision faces. Their fine render
        # triangles are the independent geometric oracle for the child colliders.
        check(site+' child collision equals parent fine surface',collision==parent['triangles'])
        for q,fine in children.items():
            for step in [2,4,8]:
                coarse=meshes[q[:3]+(step,)]
                check(f'{site} {q[:2]} step {step} boundary',coarse['boundary']==fine['boundary'],fine_edges=len(fine['boundary']),coarse_edges=len(coarse['boundary']))
        check(site+' no repeated-position triangles or >2 edge incidence',all(m['degenerate']==0 and m['nonmanifold']==0 for m in meshes.values()),
              defective_meshes=[dict(request=q,degenerate=m['degenerate'],nonmanifold=m['nonmanifold'],indexed_nonmanifold=m['indexed_nonmanifold'],after_removing_degenerate=m['after_removing_degenerate'],examples=m['bad_edge_examples'],indexed_examples=m['indexed_bad_edge_examples']) for q,m in meshes.items() if m['degenerate'] or m['nonmanifold']])
        summary.append(dict(site=site,triangles_by_step={str(step):sum(m['count'] for q,m in meshes.items() if q[2]==32 and q[3]==step) for step in [1,2,4,8]},mesh_hashes={r['file']:hashlib.sha256((project/'reports'/r['file']).read_bytes()).hexdigest() for r in rows}))
    for face in raw['ambiguous_faces']:
        signs=[sample['density']<0 for sample in face]
        for sample in face:
            sample['inside']=sample['density']<0
        check('retained ambiguous face has four sign crossings',sum(signs[i]!=signs[(i+1)%4] for i in range(4))==4)
    result=dict(failures=sum(not c['passed'] for c in checks),checks=checks,summary=summary,native_samples=raw['rows'],ambiguous_faces=raw['ambiguous_faces'],degenerate_corner_density=raw['degenerate_corner_density'],
                elapsed_seconds=time.perf_counter()-begin,
                source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'tests/terrain_boundary_probe.gd',Path(__file__).resolve(),library]},
                scope='Exact render/collision fine partition and open-edge preservation under interior simplification. No shading continuity, error bound, mixed-size T-junction proof, publication or GPU qualification.')
    (ROOT/'reports/terrain_boundary_probe.json').write_text(json.dumps(result,indent=2)+'\n')
    print(f"{result['failures']} failures; {result['elapsed_seconds']:.2f}s")
    raise SystemExit(1 if result['failures'] else 0)
