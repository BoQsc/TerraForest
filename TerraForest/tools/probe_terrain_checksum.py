"""Verify terrain CRC32C portability, archive compatibility and atomic rejection."""
from pathlib import Path
import hashlib,json,os,subprocess
from bootstrap_native import ROOT,CACHE,bootstrap

info=bootstrap()
folder=ROOT/'.build/terrain_checksum_probe'
folder.mkdir(parents=True,exist_ok=True)
native=ROOT/'addons/volumetric_terrain/native'
source=ROOT/'tests/native/terrain_checksum_probe.cpp'
exe=folder/'probe.exe'
command=[info['zig'],'c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-fno-exceptions','-fno-sanitize=undefined','-ffp-contract=off','-DTERRAFOREST_TYPED_BRIDGE','-I',str(native),str(source),str(native/'core.cpp'),'-o',str(exe)]
env=os.environ.copy()
env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache')
env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
compiled=subprocess.run(command,capture_output=True,text=True,env=env,timeout=120)
(folder/'compile.log').write_text(compiled.stdout+compiled.stderr,encoding='utf-8')
if compiled.returncode:raise RuntimeError((folder/'compile.log').read_text())
run=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30)
(folder/'run.log').write_text(run.stdout+run.stderr,encoding='utf-8')
rows=[json.loads(line) for line in run.stdout.splitlines()]
files=[source,Path(__file__).resolve(),native/'core.cpp',native/'core.h',native/'terrain_checksum.hpp']
report={'checks':rows,'failures':sum(not r['passed'] for r in rows),'source_hashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(ROOT/'reports/terrain_checksum.json').write_text(json.dumps(report,indent=2)+'\n')
print(run.stdout,flush=True)
raise SystemExit(bool(run.returncode or report['failures'] or len(rows)!=14))
