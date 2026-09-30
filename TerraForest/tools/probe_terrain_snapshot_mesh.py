"""Exercise the opt-in snapshot API through the release extension in Godot."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--godot',required=True);args=parser.parse_args()
subprocess.run(['python',str(ROOT/'tools/build_native.py'),'--addon','volumetric_terrain','--target','template_release'],cwd=ROOT,check=True,timeout=180)
script=ROOT/'tests/terrain_snapshot_mesh_probe.gd'
library=ROOT/'addons/volumetric_terrain/bin/terrain_core.windows.template_release.x86_64.dll'
with tempfile.TemporaryDirectory(prefix='snapshot_mesh_',dir=ROOT/'.build') as temporary:
    project=Path(temporary);addon=project/'addons/volumetric_terrain';(addon/'bin').mkdir(parents=True)
    shutil.copy2(library,addon/'bin'/library.name);shutil.copy2(script,project/'probe.gd')
    shutil.copy2(ROOT/'addons/volumetric_terrain/mesh_codec.gd',addon/'mesh_codec.gd')
    (addon/'terrain_core.gdextension').write_text('[configuration]\nentry_symbol="terrain_library_init"\ncompatibility_minimum="4.7"\n[libraries]\nwindows.debug.x86_64="res://addons/volumetric_terrain/bin/'+library.name+'"\nwindows.release.x86_64="res://addons/volumetric_terrain/bin/'+library.name+'"\n')
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Density command probe"\n')
    try:
        run=subprocess.run([args.godot,'--headless','--path',str(project),'--script','res://probe.gd'],capture_output=True,text=True,timeout=45)
    except subprocess.TimeoutExpired as error:
        def decode(value): return value.decode('utf-8',errors='replace') if isinstance(value,bytes) else (value or '')
        log=decode(error.stdout)+'\n'+decode(error.stderr)
        (ROOT/'reports/terrain_snapshot_mesh.log').write_text(log,encoding='utf-8')
        print(log,flush=True)
        raise SystemExit('Snapshot bridge probe timed out; captured diagnostics retained')
    log=run.stdout+'\n'+run.stderr;(ROOT/'reports/terrain_snapshot_mesh.log').write_text(log,encoding='utf-8');print(log)
    if not (project/'reports/command.json').exists():raise SystemExit(1)
    report=json.loads((project/'reports/command.json').read_text())
    sources=[ROOT/'addons/volumetric_terrain/native/terrain_binding.cpp',*sorted((ROOT/'addons/volumetric_terrain/native/experimental').glob('*.hpp')),script,library,Path(__file__).resolve(),ROOT/'tools/build_native.py',ROOT/'addons/volumetric_terrain/native/core.cpp',ROOT/'addons/volumetric_terrain/native/experimental/density_ray.hpp']
    sources.extend(ROOT/p for p in ['addons/volumetric_terrain/mesh_codec.gd','addons/volumetric_terrain/native/core.h','addons/volumetric_terrain/native/terrain_collision.cpp','addons/volumetric_terrain/native/terrain_collision.hpp'])
    report.update(source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},adoption_qualified=False,scope='Snapshot adapter and bounded shaded packet conversion. Headless mesh-resource and physics test for two brick publication, block removal and vertical neighbor face exposure. No gameplay stream/cache adoption, rendered visual inspection, frame budget or FPS qualification.')
    (ROOT/'reports/terrain_snapshot_mesh.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(bool(run.returncode or report['failures'] or re.search(r'(?m)^(SCRIPT ERROR|ERROR:|WARNING: ObjectDB instances leaked)',log)))
