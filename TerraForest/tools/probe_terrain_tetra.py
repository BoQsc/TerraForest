"""Build isolated C++ geometry candidate with pinned Zig; reject topology/boundary failures."""
from pathlib import Path
from collections import Counter
import hashlib
import gzip
import json
import os
import struct
import subprocess
import time
from bootstrap_native import ROOT,CACHE,bootstrap

begin=time.perf_counter()
toolchain=bootstrap()
folder=ROOT/'.build/tetra_probe'
folder.mkdir(exist_ok=True)
native=ROOT/'addons/volumetric_terrain/native'
source=ROOT/'tests/native/terrain_tetra_probe.cpp'
exe=folder/'probe.exe'
command=[toolchain['zig'],'c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-fno-exceptions','-fno-sanitize=undefined','-ffp-contract=off','-DTERRAFOREST_TYPED_BRIDGE','-I',str(native),str(source),str(native/'core.cpp'),'-o',str(exe)]
env=os.environ.copy()
env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache')
env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
subprocess.run(command,check=True,timeout=120,env=env)
run=subprocess.run([str(exe),str(folder)],capture_output=True,text=True,check=True,timeout=60)
samples=[json.loads(line) for line in run.stdout.splitlines()]
controls=[json.loads(line) for line in run.stderr.splitlines()]
storage_controls=[row for row in controls if 'control_peak_crossings' in row]
sampler_controls=[row for row in controls if row['name']=='world-edge sampler']
limit_controls=[row for row in controls if row['name'] in ['vertex limit','index limit','cancellation','exact output limits and recovery']]
thread_controls=[row for row in controls if row['name']=='threaded per-world epoch cancellation']

def decode(path):
    data=path.read_bytes();nv,ni=struct.unpack_from('<II',data)
    assert len(data)==8+12*nv+4*ni and ni%3==0
    points=[data[8+12*i:20+12*i] for i in range(nv)]
    xyz=[struct.unpack('<3f',p) for p in points]
    indices=struct.unpack_from('<'+str(ni)+'I',data,8+12*nv)
    triangles=Counter();unoriented=Counter();edges=Counter();directed=Counter();zero=0;links={}
    for i in range(0,ni,3):
        ia,ib,ic=indices[i:i+3];a,b,c=points[ia],points[ib],points[ic]
        triangles[min((a,b,c),(b,c,a),(c,a,b))]+=1
        unoriented[tuple(sorted((a,b,c)))]+=1
        u=[xyz[ib][k]-xyz[ia][k] for k in range(3)]
        v=[xyz[ic][k]-xyz[ia][k] for k in range(3)]
        cross=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
        zero+=sum(n*n for n in cross)==0
        for u,v in [(a,b),(b,c),(c,a)]:
            edges[tuple(sorted((u,v)))]+=1;directed[(u,v)]+=1
        for center,u,v in [(a,b,c),(b,c,a),(c,a,b)]:
            link=links.setdefault(center,{})
            link.setdefault(u,set()).add(v);link.setdefault(v,set()).add(u)
    overused=sum(n>2 for n in edges.values())
    orientation=sum(n==2 and directed[(a,b)]!=directed[(b,a)] for (a,b),n in edges.items())
    bad_links=0
    boundary_vertices={p for e,n in edges.items() if n==1 for p in e}
    for center,link in links.items():
        pending=[next(iter(link))];seen=set()
        while pending:
            p=pending.pop()
            if p in seen: continue
            seen.add(p);pending.extend(link[p]-seen)
        degrees=[len(v) for v in link.values()]
        bad_links+=len(seen)!=len(link) or any(n not in [1,2] for n in degrees) or degrees.count(1)!=(2 if center in boundary_vertices else 0)
    _,x,z,size=map(int,path.stem.split('_'))
    limits=[(x,x+size),(0,256),(z,z+size)]
    interior_open=0
    for (a,b),n in edges.items():
        if n!=1: continue
        pa,pb=struct.unpack('<3f',a),struct.unpack('<3f',b)
        interior_open+=not any(pa[axis]==pb[axis]==plane for axis in range(3) for plane in limits[axis])
    return triangles,dict(vertices=nv,triangles=ni//3,duplicate_faces=sum(n-1 for n in unoriented.values() if n>1),zero_area=zero,overused_edges=overused,inconsistent_orientation=orientation,bad_vertex_links=bad_links,interior_open_edges=interior_open,sha256=hashlib.sha256(data).hexdigest())

checks=[];meshes={}
expected=[]
for site,x,z in [(0,960,960),(1,1280,1280),(2,1280,1280)]:
    expected.append(folder/f'{site}_{x}_{z}_32.bin')
    expected.extend(folder/f'{site}_{x+dx}_{z+dz}_16.bin' for dz in [0,16] for dx in [0,16])
for path in expected:
    tris,stats=decode(path);meshes[path.stem]=(tris,stats)
    checks.append(dict(name=path.stem,passed=not(stats['zero_area'] or stats['duplicate_faces'] or stats['overused_edges'] or stats['inconsistent_orientation'] or stats['bad_vertex_links'] or stats['interior_open_edges']),**stats))
for site,x,z in [(0,960,960),(1,1280,1280),(2,1280,1280)]:
    whole=meshes[f'{site}_{x}_{z}_32'][0];combined=Counter()
    for dz in [0,16]:
        for dx in [0,16]: combined.update(meshes[f'{site}_{x+dx}_{z+dz}_16'][0])
    checks.append(dict(name=f'{site} exact fine partition',passed=whole==combined,missing=sum((whole-combined).values()),extra=sum((combined-whole).values())))
baseline_path=ROOT/'docs/evidence/terrain_tetra/terrain_tetra_probe.json.gz'
baseline=json.loads(gzip.decompress(baseline_path.read_bytes()))
fingerprints={c['name']:c['sha256'] for c in baseline['checks'] if 'sha256' in c}
checks.append(dict(name='all optimized meshes equal committed reference bytes',passed=len(fingerprints)==15 and all(meshes[name][1]['sha256']==digest for name,digest in fingerprints.items())))
checks.append(dict(name='all quantized field samples match World::sample',passed=len(samples)==15 and all(s['sample_parity'] for s in samples)))
checks.append(dict(name='five paired slab-retirement controls preserve exact geometry per fixture',passed=len(samples)==15 and all(s['mesh_parity'] and len(s['meshing_samples_ms'])==5 and len(s['control_meshing_samples_ms'])==5 for s in samples)))
checks.append(dict(name='crossing map stays within single-slab edge bound including alternating layers',passed=len(storage_controls)==1 and all(s['peak_crossings']<=36*s['size']**2 and s['peak_crossings']<s['control_peak_crossings'] and s['mesh_parity'] for s in samples+storage_controls)))
checks.append(dict(name='two-plane sampling preserves all densities and geometry with bounded scratch payload',passed=len(samples)==15 and all(s['streamed_parity'] and s['density_plane_bytes']==8*(s['size']+1)**2 and s['sampler_payload_bytes']==16*(s['size']+1)**2 for s in samples)))
checks.append(dict(name='rolling sampler matches authoritative samples at and across world edges',passed=len(sampler_controls)==3 and all(s['sample_parity'] for s in sampler_controls)))
checks.append(dict(name='output limits and cancellation discard partial meshes and recover exactly',passed=len(limit_controls)==12 and all(s.get('empty_failure',s.get('mesh_parity',False)) for s in limit_controls)))
checks.append(dict(name='native epoch cancels an in-progress worker without affecting another world',passed=len(thread_controls)==1 and all(s['cancelled_after_vertices']>0 and s['discarded'] and s['other_world_unchanged'] and s['retry_parity'] for s in thread_controls)))
result=dict(failures=sum(not c['passed'] for c in checks),checks=checks,native_samples=samples,storage_controls=storage_controls,sampler_controls=sampler_controls,limit_controls=limit_controls,thread_controls=thread_controls,elapsed_seconds=time.perf_counter()-begin,
            adoption_qualified=False,build_command=command,toolchain_lock_sha256=toolchain['lock_sha256'],executable_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(),
            reference_report_sha256=hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
            hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,Path(__file__).resolve(),native/'core.cpp',native/'core.h',native/'platform.h',native/'geometry_regions.hpp']},
            scope='Isolated tetrahedral geometry prototype with full-buffer controls and a two-plane streaming sampler. Sampler payload excludes reference buffers, output geometry and allocator overhead. Changes interpolation and zero convention; no LOD, visual-error, material, shading, collider, GPU or runtime qualification.')
(ROOT/'reports').mkdir(exist_ok=True)
(ROOT/'reports/terrain_tetra_probe.json').write_text(json.dumps(result,indent=2)+'\n')
for c in checks: print(('PASS ' if c['passed'] else 'FAIL ')+c['name'],c.get('zero_area',''),c.get('overused_edges',''))
print(json.dumps(samples))
print('Failures:',result['failures'])
raise SystemExit(bool(result['failures']))
