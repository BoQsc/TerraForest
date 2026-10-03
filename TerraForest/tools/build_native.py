"""Incrementally compile only TerraForest C++ against the pinned prebuilt godot-cpp SDK."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import time
from bootstrap_native import ROOT, LOCK, CACHE, bootstrap, digest

def run_logged(command, env, log):
    with log.open('w',encoding='utf-8') as stream:
        result=subprocess.run(command,env=env,stdout=stream,stderr=subprocess.STDOUT)
    if result.returncode:
        with log.open('rb') as stream:
            stream.seek(max(0,log.stat().st_size-16000))
            print(stream.read().decode('utf-8',errors='replace'),flush=True)
        raise RuntimeError(f'Native command failed ({result.returncode}); complete log: {log}')

def build(target, addon_name='world_runtime'):
    info=bootstrap()
    sdk=Path(info['godot_cpp'])/'godot-cpp'
    metadata=json.loads((sdk/'BUILD_INFO.json').read_text())
    expected={'api_version':'4.7','godot_cpp_sha':LOCK['godot_cpp_commit'],'variant':'windows-x86_64-zig','compiler':'zig-0.16.0','platform':'windows','arch':'x86_64','precision':'single'}
    for name,value in expected.items():
        if metadata.get(name)!=value:raise RuntimeError(f'SDK ABI metadata mismatch: {name}')
    addon=ROOT/'addons'/addon_name
    native=addon/'native'
    work=ROOT/'.build/native'/addon_name/target
    work.mkdir(parents=True,exist_ok=True)
    output=addon/'bin'/f'{addon_name}.windows.{target}.x86_64.dll'
    if addon_name=='volumetric_terrain':
        output=addon/'bin'/('terrain_core.windows.x86_64.dll' if target=='template_debug' else 'terrain_core.windows.template_release.x86_64.dll')
    output.parent.mkdir(exist_ok=True)
    library=sdk/'bin'/f'libgodot-cpp.windows.{target}.x86_64.a'
    compiler=[info['zig'],'c++','-target','x86_64-windows-gnu']
    flags=['-std=c++17','-fno-exceptions','-fno-sanitize=undefined','-fvisibility=hidden','-ffp-contract=off','-Wno-nullability-completeness','-DGDEXTENSION','-DWINDOWS_ENABLED','-DTHREADS_ENABLED','-O2' if target=='template_debug' else '-O3']
    if target=='template_debug':flags+=['-DDEBUG_ENABLED','-g']
    if addon_name=='volumetric_terrain':flags+=['-DTERRAFOREST_TYPED_BRIDGE']
    for directory in ['include','gen/include','gdextension']:flags+=['-I',str(sdk/directory)]
    env=os.environ.copy()
    env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache')
    env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
    state_path=work/'state.json'
    state=json.loads(state_path.read_text()) if state_path.exists() else {}
    fingerprint=hashlib.sha256((info['lock_sha256']+json.dumps(flags)+digest(library)).encode())
    for header in sorted([*native.rglob('*.hpp'),*native.rglob('*.h')]):
        fingerprint.update(str(header.relative_to(native)).encode())
        fingerprint.update(header.read_bytes())
    common=fingerprint.hexdigest()
    objects=[]; compiled=[]; records={}
    started=time.perf_counter()
    for source in sorted(native.glob('*.cpp')):
        if addon_name=='volumetric_terrain' and source.name=='godot_bridge.cpp':continue
        signature=hashlib.sha256((common+digest(source)).encode()).hexdigest()
        obj=work/(source.stem+'.o')
        records[source.name]=signature
        if not obj.exists() or state.get(source.name)!=signature:
            print('Compiling extension:',source.name,flush=True)
            run_logged(compiler+flags+['-c',str(source),'-o',str(obj)],env,work/(source.stem+'.log'))
            compiled.append(source.name)
        objects.append(obj)
    signature=hashlib.sha256(json.dumps(records,sort_keys=True).encode()).hexdigest()
    linked=bool(compiled or not output.exists() or state.get('link')!=signature)
    if linked:
        pending=work/(addon_name+'.pending.dll')
        print('Linking extension against prebuilt:',library.name,flush=True)
        run_logged(compiler+['-shared',*map(str,objects),str(library),'-Wl,--no-undefined','-o',str(pending)],env,work/'link.log')
        pending.replace(output)
    records['link']=signature
    state_path.write_text(json.dumps(records,indent=2))
    report={'target':target,'compiled_extension_sources':compiled,'godot_cpp_sources_compiled':0,'linked':linked,'seconds':time.perf_counter()-started,'output':str(output),'sha256':digest(output),'sdk':metadata}
    (ROOT/'reports').mkdir(exist_ok=True)
    report['addon']=addon_name
    report_name=f'native_build_{target}.json' if addon_name=='world_runtime' else f'{addon_name}_build_{target}.json'
    (ROOT/'reports'/report_name).write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target',choices=['template_debug','template_release','all'],default='template_debug')
    parser.add_argument('--addon',choices=['world_runtime','volumetric_water','volumetric_terrain','structures','player_runtime','vehicle_runtime','vegetation_runtime','all'],default='all')
    args=parser.parse_args()
    for addon in (['world_runtime','volumetric_water','volumetric_terrain','structures','player_runtime','vehicle_runtime','vegetation_runtime'] if args.addon=='all' else [args.addon]):
        for target in (['template_debug','template_release'] if args.target=='all' else [args.target]):build(target,addon)
