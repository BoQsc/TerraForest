"""Inject allocation failure into real terrain edits and audit exact rollback."""
from pathlib import Path
import hashlib,json,os,subprocess
from bootstrap_native import ROOT,CACHE,bootstrap

info=bootstrap();folder=ROOT/'.build/terrain_edit_atomicity'
folder.mkdir(parents=True,exist_ok=True)
native=ROOT/'addons/volumetric_terrain/native'
source=ROOT/'tests/native/terrain_edit_atomicity_probe.cpp';exe=folder/'probe.exe'
command=[info['zig'],'c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-fno-exceptions','-fno-sanitize=undefined','-ffp-contract=off','-DTERRAFOREST_TYPED_BRIDGE','-I',str(native),str(source),str(native/'core.cpp'),'-o',str(exe)]
env=os.environ.copy();env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache');env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
compiled=subprocess.run(command,capture_output=True,text=True,env=env,timeout=120)
(folder/'compile.log').write_text(compiled.stdout+compiled.stderr,encoding='utf-8')
if compiled.returncode:raise RuntimeError((folder/'compile.log').read_text())
candidate=folder/"candidate";candidate.mkdir(exist_ok=True)
expected=json.loads((ROOT/'tests/fixtures/terrain_edit_atomicity/successful_fields.json').read_text())['hashes']
for name in expected:
    target=(candidate/name).resolve()
    if candidate.resolve() not in target.parents:raise RuntimeError('Fixture path escaped candidate folder')
    if target.exists():target.unlink()
result=subprocess.run([str(exe)],cwd=candidate,capture_output=True,text=True,timeout=20)
(folder/'run.log').write_text(result.stdout+result.stderr,encoding='utf-8')
rows=[json.loads(line) for line in result.stdout.splitlines()]
rows.append({'case':'native_process_exit','passed':result.returncode==0,'exit_code':result.returncode})
actual={name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in expected if (candidate/name).exists()}
rows.append({'case':'prechange_field_and_receipt_parity','passed':actual==expected,'hashes':actual})
report={'failures':sum(not r['passed'] for r in rows),'checks':rows,'exit_code':result.returncode,'source_hashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,native/'core.cpp',native/'core.h',native/'platform.h']}}
(ROOT/'reports/terrain_edit_atomicity.json').write_text(json.dumps(report,indent=2)+'\n')
print(result.stdout,flush=True)
raise SystemExit(bool(result.returncode or report['failures'] or len(rows)<2))
