"""Cook candidate fixtures through the existing native Godot collision interface."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, struct, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot',required=True)
args=parser.parse_args()
# Rebuild and verify fixtures instead of silently accepting stale .build output.
subprocess.run(['python',str(ROOT/'tools/probe_terrain_tetra.py')],cwd=ROOT,check=True,stdout=subprocess.DEVNULL,timeout=120)
native_report=json.loads((ROOT/'reports/terrain_tetra_probe.json').read_text())
source=ROOT/'addons/volumetric_terrain'
library=source/'bin/terrain_core.windows.template_release.x86_64.dll'
script=ROOT/'tests/terrain_candidate_collision_probe.gd'
with tempfile.TemporaryDirectory(prefix='candidate_collision_',dir=ROOT/'.build') as temporary:
    project=Path(temporary);addon=project/'addons/volumetric_terrain'
    (addon/'bin').mkdir(parents=True);(project/'faces').mkdir()
    shutil.copy2(library,addon/'bin'/library.name)
    (addon/'terrain_core.gdextension').write_text('[configuration]\nentry_symbol="terrain_library_init"\ncompatibility_minimum="4.7"\n[libraries]\nwindows.debug.x86_64="res://addons/volumetric_terrain/bin/'+library.name+'"\nwindows.release.x86_64="res://addons/volumetric_terrain/bin/'+library.name+'"\n')
    shutil.copy2(script,project/'probe.gd')
    fixtures=[];hashes={}
    for check in native_report['checks']:
        if 'sha256' not in check: continue
        path=ROOT/'.build/tetra_probe'/(check['name']+'.bin');data=path.read_bytes()
        assert hashlib.sha256(data).hexdigest()==check['sha256']
        nv,ni=struct.unpack_from('<II',data)
        indices=struct.unpack_from('<'+str(ni)+'I',data,8+12*nv)
        assert ni%3==0 and all(i<nv for i in indices)
        faces=b''.join(data[8+12*i:20+12*i] for i in indices)
        name=path.stem+'.faces';(project/'faces'/name).write_bytes(faces)
        fixtures.append(name);hashes[name]=hashlib.sha256(faces).hexdigest()
    assert len(fixtures)==15
    (project/'fixtures.json').write_text(json.dumps(fixtures))
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Candidate collision probe"\n')
    run=subprocess.run([args.godot,'--headless','--path',str(project),'--script','res://probe.gd'],capture_output=True,text=True,timeout=120)
    log=run.stdout+'\n'+run.stderr
    (ROOT/'reports/terrain_candidate_collision.log').write_text(log,encoding='utf-8')
    print(log)
    if not (project/'reports/collision.json').exists(): raise SystemExit(1)
    report=json.loads((project/'reports/collision.json').read_text())
    report.update(fixture_hashes=hashes,native_probe_sha256=hashlib.sha256((ROOT/'reports/terrain_tetra_probe.json').read_bytes()).hexdigest(),source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [script,library,Path(__file__).resolve()]},adoption_qualified=False)
    (ROOT/'reports/terrain_candidate_collision.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(bool(run.returncode or report['failures'] or re.search(r'(?m)^(SCRIPT ERROR|ERROR:|WARNING: ObjectDB instances leaked)',log)))
