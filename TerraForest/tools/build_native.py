"""Incremental native builds with one pinned godot-cpp Dictionary lifetime repair."""
from pathlib import Path
from contextlib import nullcontext
import argparse
import hashlib
import json
import os
import subprocess
import time
from bootstrap_native import ROOT, LOCK, CACHE, bootstrap, digest
from cleanup_generation_copies import lease

ADDONS = ['world_runtime','volumetric_water','volumetric_terrain','structures',
          'player_runtime','vehicle_runtime','vegetation_runtime']
SHARED_HEADERS = {
    'volumetric_terrain': ['world_runtime/native/' + name for name in ('landform_shapes.hpp','island_lake_modules.hpp','island_lake_field.hpp','shore_habitat.hpp','biome_field.hpp')],
    'volumetric_water': ['volumetric_terrain/native/' + name
                         for name in ('surface_cell.hpp','density_surface.hpp','platform.h')],
    'player_runtime': ['structures/native/block_word.hpp'],
    'vegetation_runtime': ['world_runtime/native/'+name for name in ('biome_field.hpp','landform_shapes.hpp','shore_habitat.hpp')],
}

def build_lease():
    if os.name != 'nt':
        return nullcontext()
    reports = ROOT/'reports'
    reports.mkdir(exist_ok=True)
    return lease(reports/'native_build')

def run_logged(command, env, log):
    with log.open('w',encoding='utf-8') as stream:
        result=subprocess.run(command,env=env,stdout=stream,stderr=subprocess.STDOUT)
    if result.returncode:
        with log.open('rb') as stream:
            stream.seek(max(0,log.stat().st_size-16000))
            print(stream.read().decode('utf-8',errors='replace'),flush=True)
        raise RuntimeError(f'Native command failed ({result.returncode}); complete log: {log}')

def dictionary_binding(sdk, target, compiler, flags, env, lock_hash):
    # Maintenance of the existing MIT binding exception (EX-002). Keep the
    # SDK untouched and retain its copyright/license header in the derived TU.
    # The pinned move assignment abandons its previous dictionary reference.
    # Equivalent upstream repair: godotengine/godot-cpp#2055.
    source=sdk/'gen/src/variant/dictionary.cpp'
    expected='cbeecb1484782dc2896a57061e52d7d2c0d4a90f6db2e27186b5eb7aab7f4ecd'
    if digest(source)!=expected:
        raise RuntimeError('Dictionary binding source changed; review/remove the pinned lifetime repair')
    original=source.read_text(encoding='utf-8')
    start=original.index('Dictionary &Dictionary::operator=(Dictionary &&p_other) {')
    end=original.index('\n}',start)+2
    repaired=original[:start]+('Dictionary &Dictionary::operator=(Dictionary &&p_other) {\n'
        '\tstd::swap(opaque, p_other.opaque);\n\treturn *this;\n}')+original[end:]
    binding_flags=[flag for flag in flags if flag!='-DTERRAFOREST_TYPED_BRIDGE']
    signature=hashlib.sha256((lock_hash+json.dumps(binding_flags)+repaired).encode()).hexdigest()
    work=ROOT/'.build/native/bindings'/target/signature
    work.mkdir(parents=True,exist_ok=True)
    generated=work/'dictionary.cpp'
    obj=work/'dictionary.o'
    compiled=not obj.exists()
    if compiled:
        generated.write_text(repaired,encoding='utf-8')
        pending=work/'dictionary.pending.o'
        print('Compiling pinned Dictionary lifetime repair:',target,flush=True)
        run_logged(compiler+binding_flags+['-c',str(generated),'-o',str(pending)],env,work/'compile.log')
        pending.replace(obj)
    return obj,dict(id='dictionary_move_assignment_v1',source_sha256=expected,
                    source_commit=LOCK['godot_cpp_commit'],signature=signature,
                    object_sha256=digest(obj),compiled=compiled)


def build(target, addon_name='world_runtime', check_only=False):
    info=bootstrap()
    sdk=Path(info['godot_cpp'])/'godot-cpp'
    metadata=json.loads((sdk/'BUILD_INFO.json').read_text())
    expected={'api_version':'4.7','godot_cpp_sha':LOCK['godot_cpp_commit'],'variant':'windows-x86_64-zig','compiler':'zig-0.16.0','platform':'windows','arch':'x86_64','precision':'single'}
    for name,value in expected.items():
        if metadata.get(name)!=value:raise RuntimeError(f'SDK ABI metadata mismatch: {name}')
    addon=ROOT/'addons'/addon_name
    native=addon/'native'
    work=ROOT/'.build/native'/addon_name/target
    output=addon/'bin'/f'{addon_name}.windows.{target}.x86_64.dll'
    if addon_name=='volumetric_terrain':
        output=addon/'bin'/('terrain_core.windows.x86_64.dll' if target=='template_debug' else 'terrain_core.windows.template_release.x86_64.dll')
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
    shared_headers = [ROOT/'addons'/name for name in SHARED_HEADERS.get(addon_name, ())]
    for header in sorted([*native.rglob('*.hpp'),*native.rglob('*.h'),*shared_headers]):
        fingerprint.update(str(header.relative_to(ROOT)).encode())
        fingerprint.update(header.read_bytes())
    common=fingerprint.hexdigest()
    sources=[source for source in sorted(native.glob('*.cpp'))
             if addon_name!='volumetric_terrain' or source.name!='godot_bridge.cpp']
    signatures={source.name:hashlib.sha256((common+digest(source)).encode()).hexdigest()
                for source in sources}
    report_name=f'native_build_{target}.json' if addon_name=='world_runtime' else f'{addon_name}_build_{target}.json'
    report_path=ROOT/'reports'/report_name
    if check_only:
        if not output.is_file() or not report_path.is_file():
            return False
        receipt=json.loads(report_path.read_text())
        recorded={name:signature for name,signature in state.items() if name.endswith('.cpp')}
        return (signatures==recorded and state.get('link') and receipt.get('sha256')==digest(output)
                and receipt.get('link_signature') in (None,state['link']))
    work.mkdir(parents=True,exist_ok=True)
    output.parent.mkdir(exist_ok=True)
    objects=[]; compiled=[]; records={}
    started=time.perf_counter()
    for source in sources:
        signature=signatures[source.name]
        obj=work/(source.stem+'.o')
        records[source.name]=signature
        if not obj.exists() or state.get(source.name)!=signature:
            print('Compiling extension:',source.name,flush=True)
            run_logged(compiler+flags+['-c',str(source),'-o',str(obj)],env,work/(source.stem+'.log'))
            compiled.append(source.name)
        objects.append(obj)
    binding,repair=dictionary_binding(sdk,target,compiler,flags,env,info['lock_sha256'])
    records['dictionary_binding']=repair['object_sha256']
    signature=hashlib.sha256(json.dumps(records,sort_keys=True).encode()).hexdigest()
    linked=bool(compiled or not output.exists() or state.get('link')!=signature or
                not report_path.is_file() or json.loads(report_path.read_text()).get('sha256')!=digest(output))
    if linked:
        pending=work/(addon_name+'.pending.dll')
        print('Linking extension against prebuilt:',library.name,flush=True)
        # Resolve the complete Dictionary TU before archive extraction so the
        # defective prebuilt Dictionary object is not linked into this DLL.
        run_logged(compiler+['-shared',*map(str,objects),str(binding),str(library),'-Wl,--no-undefined','-o',str(pending)],env,work/'link.log')
        pending.replace(output)
    records['link']=signature
    state_path.write_text(json.dumps(records,indent=2))
    report={'target':target,'compiled_extension_sources':compiled,'godot_cpp_sources_compiled':int(repair['compiled']),'binding_repair':repair,'linked':linked,'seconds':time.perf_counter()-started,'output':str(output),'sha256':digest(output),'sdk':metadata}
    (ROOT/'reports').mkdir(exist_ok=True)
    report['addon']=addon_name
    report['link_signature']=signature
    report_path.write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target',choices=['template_debug','template_release','all'],default='template_debug')
    parser.add_argument('--addon',choices=[*ADDONS,'all'],default='all')
    args=parser.parse_args()
    with build_lease():
        for addon in (ADDONS if args.addon=='all' else [args.addon]):
            for target in (['template_debug','template_release'] if args.target=='all' else [args.target]):build(target,addon)
