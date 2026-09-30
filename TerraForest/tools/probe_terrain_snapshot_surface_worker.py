"""Measure bounded region capture and geometry independence after world release."""
from pathlib import Path
import hashlib,json,os,subprocess
from bootstrap_native import ROOT,CACHE,bootstrap

toolchain=bootstrap()
folder=ROOT/'.build/snapshot_surface_worker_probe'
folder.mkdir(exist_ok=True)
native=ROOT/'addons/volumetric_terrain/native'
source=ROOT/'tests/native/terrain_snapshot_surface_worker_probe.cpp'
exe=folder/'probe.exe'
command=[toolchain['zig'],'c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-fno-exceptions','-fno-sanitize=undefined','-ffp-contract=off','-DTERRAFOREST_TYPED_BRIDGE','-I',str(native),str(source),str(native/'core.cpp'),'-o',str(exe)]
env=os.environ.copy()
env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache')
env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
subprocess.run(command,check=True,env=env,timeout=120)
run=subprocess.run([str(exe)],capture_output=True,text=True,timeout=60)
rows=[json.loads(line) for line in run.stdout.splitlines()]
assert len(rows)==4,run.stderr
files=[source,Path(__file__).resolve(),native/'core.cpp',native/'core.h',native/'platform.h',*sorted((native/'experimental').glob('*.hpp'))]
report=dict(samples=rows,failures=sum(not row['passed'] for row in rows),adoption_qualified=False,scope='Bounded native snapshot worker lifecycle experiment; no concurrent query latency, normals, materials, lighting or FPS qualification.',source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files})
(ROOT/'reports/terrain_snapshot_surface_worker.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report['samples'],indent=2))
raise SystemExit(bool(run.returncode or report['failures']))
