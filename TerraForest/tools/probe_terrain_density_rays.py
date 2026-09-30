"""Check frozen mesh-ray segments against the quantized trilinear terrain field."""
from pathlib import Path
import gzip,hashlib,json,os,subprocess
from bootstrap_native import ROOT,CACHE,bootstrap
toolchain=bootstrap();folder=ROOT/'.build/density_ray_probe';folder.mkdir(exist_ok=True)
sources=[ROOT/'docs/evidence/terrain_candidate_collision/terrain_candidate_collision.json.gz',ROOT/'docs/evidence/terrain_exact_zero/terrain_exact_zero_collision.json.gz']
rows=[]
for source in sources:
    report=json.loads(gzip.decompress(source.read_bytes()))
    for row in report['rays']:
        if not row['hit']:rows.append(dict(row,source=str(source.relative_to(ROOT))))
assert len(rows)==22
input_file=folder/'input.txt'
input_file.write_text('\n'.join(' '.join(map(str,[i,int(row['fixture'].split('_')[0]),*row['a'],*row['b'],*row['c']])) for i,row in enumerate(rows))+'\n')
native=ROOT/'addons/volumetric_terrain/native';source=ROOT/'tests/native/terrain_density_ray_probe.cpp';exe=folder/'probe.exe'
command=[toolchain['zig'],'c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-fno-exceptions','-fno-sanitize=undefined','-ffp-contract=off','-DTERRAFOREST_TYPED_BRIDGE','-I',str(native),str(source),str(native/'core.cpp'),'-o',str(exe)]
env=os.environ.copy();env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache');env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
subprocess.run(command,check=True,env=env,timeout=120)
run=subprocess.run([str(exe),str(input_file)],capture_output=True,text=True,check=True,timeout=60)
samples=[json.loads(line) for line in run.stdout.splitlines()];assert len(samples)==len(rows)
for sample,row in zip(samples,rows):
    sample.update(fixture=row['fixture'],triangle=row['triangle'],source=row['source'],passed=sample['bracketed'] and sample['distance']<.002 and sample['air_control_clear'] and sample['solid_control_clear'])
report=dict(samples=samples,failures=sum(not s['passed'] for s in samples),adoption_qualified=False,toolchain_lock_sha256=toolchain['lock_sha256'],build_command=command,source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,Path(__file__).resolve(),native/'core.cpp',native/'core.h',native/'platform.h',*sources]},scope='Frozen short segments only. Bracketed bisection of quantized trilinear field, not a complete raycaster or proof of first intersection.')
(ROOT/'reports/terrain_density_rays.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report['samples'],indent=2));print('Failures:',report['failures'])
raise SystemExit(bool(report['failures']))
