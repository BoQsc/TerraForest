# SPDX-License-Identifier: 0BSD
"""Verify a dependency ZIP in a cache-free Godot project; no gameplay qualification."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile
from package import ROOT, DEPENDENCIES

def verify(addon, engine, import_frame_delay_ms=0):
    source=ROOT/'dist'/(addon+'.zip')
    output=ROOT/'reports/addon_bundles'/addon
    if import_frame_delay_ms:
        output=output/('delay_'+str(import_frame_delay_ms))
    output.mkdir(parents=True,exist_ok=True)
    (ROOT/'.build').mkdir(exist_ok=True)
    result={'addon':addon,'archive_sha256':hashlib.sha256(source.read_bytes()).hexdigest(), 'steps':[], 'import_frame_delay_ms':import_frame_delay_ms}
    with tempfile.TemporaryDirectory(prefix='addon_'+addon+'_',dir=ROOT/'.build') as temporary:
        project=Path(temporary).resolve()
        with zipfile.ZipFile(source) as archive:
            names=archive.namelist()
            if len(names)!=len(set(names)):
                raise ValueError('Duplicate archive entries')
            for name in names:
                if project not in (project/name).resolve().parents:
                    raise ValueError('Unsafe archive path: '+name)
            manifest=json.loads(archive.read('MANIFEST.sha256.json'))
            if set(names)!=set(manifest)|{'MANIFEST.sha256.json'}:
                raise ValueError('Manifest does not cover exact archive contents')
            for name,digest in manifest.items():
                if hashlib.sha256(archive.read(name)).hexdigest()!=digest:
                    raise ValueError('Hash mismatch: '+name)
            archive.extractall(project)
        if (project/'.godot').exists():
            raise ValueError('Bundle contains editor cache')
        paths=sorted('res://'+p.relative_to(project).as_posix() for p in project.rglob('*') if p.suffix in {'.gd','.tscn','.tres','.gdshader','.gdextension'})
        result['resource_count']=len(paths)
        (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Addon Bundle Check"\n',encoding='utf-8')
        script='extends SceneTree\nfunc _initialize() -> void:\n var failures:=0\n for path in '+json.dumps(paths)+':\n  if (path.ends_with(".gdextension") and not GDExtensionManager.is_extension_loaded(path)) or load(path)==null:\n   print("FAIL resource ",path);failures+=1\n print("BUNDLE_RESOURCES ",'+str(len(paths))+'," failures=",failures)\n quit(1 if failures else 0)\n'
        (project/'bundle_check.gd').write_text(script,encoding='utf-8')
        for label,extra in [('import',['--editor','--import']),('load',['--script','res://bundle_check.gd'])]:
            command=[str(engine),'--headless','--path',str(project),*extra]
            if label=='import' and import_frame_delay_ms:
                command += ['--frame-delay',str(import_frame_delay_ms)]
            run=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=90)
            log=run.stdout+'\n'+run.stderr
            (output/(label+'.log')).write_text(log,encoding='utf-8')
            ok=run.returncode==0 and not re.search(r'(?m)^(?:SCRIPT ERROR|ERROR:|FAIL |WARNING: ObjectDB instances leaked)',log)
            result['steps'].append({'phase':label,'exit_code':run.returncode,'ok':ok})
            if not ok:
                print(log[-3000:]) # Still diagnose resource loading; import failure remains fatal.
    result['ok']=len(result['steps'])==2 and all(step['ok'] for step in result['steps'])
    (output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(addon, 'PASS' if result['ok'] else 'FAIL',result['resource_count'],'resources',flush=True)
    return result['ok']

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--addon',choices=sorted(DEPENDENCIES),required=True)
    parser.add_argument('--godot',type=Path,required=True)
    parser.add_argument('--import-frame-delay-ms',type=int,default=0,choices=range(0,2001),metavar='0..2000',help='Explicit import-only workaround for Godot issue111048; default preserves ordinary import behavior')
    args=parser.parse_args()
    return 0 if verify(args.addon,args.godot,args.import_frame_delay_ms) else 1
if __name__=='__main__':
    raise SystemExit(main())
