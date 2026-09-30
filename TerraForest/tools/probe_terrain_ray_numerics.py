"""Reject false tangent hits and skipped close roots against a quadratic oracle."""
import hashlib,json,os,subprocess
from pathlib import Path
from bootstrap_native import ROOT,CACHE,bootstrap
toolchain=bootstrap();folder=ROOT/'.build/ray_numerics';folder.mkdir(exist_ok=True)
source=ROOT/'tests/native/terrain_ray_numerics_probe.cpp';header=ROOT/'addons/volumetric_terrain/native/experimental/density_ray.hpp';exe=folder/'probe.exe'
command=[toolchain['zig'],'c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-fno-exceptions','-ffp-contract=off','-I',str(header.parent.parent),str(source),'-o',str(exe)]
env=os.environ.copy();env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache');env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
subprocess.run(command,check=True,env=env,timeout=120)
run=subprocess.run([str(exe)],check=True,capture_output=True,text=True,timeout=30)
rows=[json.loads(line) for line in run.stdout.splitlines()];assert len(rows)==33
report=dict(cases=rows,failures=sum(not r['passed'] for r in rows),source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,header,Path(__file__).resolve()]},toolchain_lock_sha256=toolchain['lock_sha256'],adoption_qualified=False,scope='Near-tangent quadratic restrictions over three coefficient scales; extended-precision oracle uses actual input coefficients. No runtime performance qualification.')
(ROOT/'reports/terrain_ray_numerics.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps([r for r in rows if not r['passed']],indent=2));print('Failures:',report['failures'])
raise SystemExit(bool(report['failures']))
