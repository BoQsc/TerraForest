# SPDX-License-Identifier: 0BSD
"""Compare complete mesh bytes against the pre-change core in independent processes."""
from pathlib import Path
import hashlib,json,os,subprocess
from bootstrap_native import ROOT,CACHE,bootstrap

def main():
    info=bootstrap()
    folder=ROOT/'.build/terrain_link_scratch'
    folder.mkdir(parents=True,exist_ok=True)
    native=ROOT/'addons/volumetric_terrain/native'
    probe=ROOT/'tests/native/terrain_link_scratch_probe.cpp'
    baseline='9b451125'
    old=subprocess.run(['git','show',baseline+':TerraForest/addons/volumetric_terrain/native/core.cpp'],cwd=ROOT,capture_output=True,check=True).stdout
    previous=folder/'previous.cpp'
    previous.write_bytes(old)
    env=os.environ.copy()
    env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache')
    env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
    report={'baseline':baseline,'scope':'60 independent native mesh cases: generators 1/9/19, three seeds, fresh/cut/add states, widths 16–256 m; complete encoded packets including normals/materials/lighting/collision. Same flags and fixtures, separate processes. No GPU/FPS or universal topology proof.','cases':{}}
    for name,source in [('before',previous),('after',native/'core.cpp')]:
        target=folder/name
        target.mkdir(exist_ok=True)
        exe=target/'probe.exe'
        command=[info['zig'],'c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-fno-exceptions','-fno-sanitize=undefined','-ffp-contract=off','-DTERRAFOREST_TYPED_BRIDGE','-I',str(native),str(probe),str(source),'-o',str(exe)]
        built=subprocess.run(command,capture_output=True,text=True,env=env,timeout=120)
        (target/'compile.log').write_text(built.stdout+built.stderr,encoding='utf-8')
        built.check_returncode()
        run=subprocess.run([str(exe),str(target)],capture_output=True,text=True,timeout=45)
        (target/'run.log').write_text(run.stdout+run.stderr,encoding='utf-8')
        run.check_returncode()
        rows=[json.loads(line) for line in run.stdout.splitlines()]
        if len(rows)!=60:raise RuntimeError('Incomplete probe')
        for row in rows:
            packet=target/(str(row['case'])+'.mesh')
            row['sha256']=hashlib.sha256(packet.read_bytes()).hexdigest()
        report['cases'][name]=rows
    report['exact_packets']=all(a['sha256']==b['sha256'] for a,b in zip(report['cases']['before'],report['cases']['after']))
    report['sources_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [probe,native/'core.cpp',previous]}
    (ROOT/'reports/terrain_link_scratch.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('TERRAIN_LINK_SCRATCH exact_packets=',report['exact_packets'],' cases=60')
    if not report['exact_packets']:raise RuntimeError('Geometry changed')

if __name__=='__main__':main()
