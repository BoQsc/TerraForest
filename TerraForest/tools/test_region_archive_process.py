"""Interrupt only a spawned test writer; verify complete root/checkpoint consistency in a new process."""
from pathlib import Path
import argparse
import json
import os
import queue
import shutil
import subprocess
import tempfile
import threading
import time

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
p.add_argument('--release',action='store_true')
args=p.parse_args()
if not args.godot:p.error('Specify --godot PATH')
engine=Path(args.godot)
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():engine=direct
build=(root/'.build').resolve();build.mkdir(exist_ok=True)
results=[]
with tempfile.TemporaryDirectory(prefix='region_crash_',dir=build) as temporary:
    workspace=Path(temporary).resolve()
    assert build in workspace.parents
    project=root
    if args.release:
        project=workspace/'project';(project/'tests').mkdir(parents=True)
        (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Region archive interruption release test"\n')
        shutil.copy2(root/'tests/region_archive_process.gd',project/'tests/region_archive_process.gd')
        for addon in ['structures','world_runtime']:
            destination=project/'addons'/addon;(destination/'bin').mkdir(parents=True)
            library=f'{addon}.windows.template_release.x86_64.dll'
            shutil.copy2(root/'addons'/addon/'bin'/library,destination/'bin'/library)
            descriptor=(root/'addons'/addon/(addon+'.gdextension')).read_text()
            (destination/(addon+'.gdextension')).write_text(descriptor.replace('template_debug','template_release'))
    for trial in range(3):
        path=workspace/f'world_{trial}.trw'
        command=[str(engine),'--headless','--path',str(project),'--script','res://tests/region_archive_process.gd','--',f'--archive-path={path}']
        owner=subprocess.Popen(command+['--archive-mode=writer'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        output=queue.Queue()
        def reader(stream=owner.stdout):
            for line in stream:output.put(line)
        collector=threading.Thread(target=reader,daemon=True);collector.start()
        lines=[]
        try:
            ready=False;deadline=time.monotonic()+45
            while time.monotonic()<deadline and not ready:
                try:line=output.get(timeout=.25)
                except queue.Empty:
                    if owner.poll() is not None:break
                    continue
                lines.append(line);ready='WRITER_READY' in line
            if not ready:raise RuntimeError('Writer did not initialize: '+''.join(lines)[-5000:])
            probe=subprocess.run(command+['--archive-mode=probe'],capture_output=True,text=True,timeout=20)
            if probe.returncode or 'PROBE_OK' not in probe.stdout:raise RuntimeError(probe.stdout+probe.stderr)
            Path(str(path)+'.continue').write_text('continue')
            pending=[];deadline=time.monotonic()+20
            while time.monotonic()<deadline and owner.poll() is None:
                pending=list(workspace.glob(path.name+'.pending.*'))
                if pending:break
                time.sleep(.001)
            if not pending or owner.poll() is not None:raise RuntimeError('No live writer with an in-progress root publication observed')
            # Exactly this Popen child is terminated. No process-name searches,
            # user editor termination, or broad directory cleanup are involved.
            owner.kill();owner.wait(timeout=10);collector.join(timeout=2)
            orphans=len(list(workspace.glob(path.name+'.pending.*')))
            verify=subprocess.run(command+['--archive-mode=verify'],capture_output=True,text=True,timeout=45)
            if verify.returncode or 'RECOVERY_OK' not in verify.stdout:raise RuntimeError(verify.stdout+verify.stderr)
            evidence=json.loads(Path(str(path)+'.verification.json').read_text())
            if not evidence['pass']:raise RuntimeError('Checkpoint reconstruction failed')
            results.append({'trial':trial,'root_and_region_lease_exclusive':True,'root_temporary_observed':True,'orphan_root_temporaries':orphans,'reconstruction':evidence})
            print(f'PASS region-root process interruption trial {trial}; exact terrain/water/block/model revisions and subsequent saves verified',flush=True)
        finally:
            if owner.poll() is None:owner.kill();owner.wait(timeout=10)
            collector.join(timeout=2);owner.stdout.close()
(root/'reports').mkdir(exist_ok=True)
report='region_archive_process_release.json' if args.release else 'region_archive_process.json'
(root/'reports'/report).write_text(json.dumps({'failures':0,'variant':'release' if args.release else 'debug','trials':results,'scope':'Abrupt process termination during observed root publication, not physical power loss; terrain/water are opaque revision-marker payloads, blocks/models are real native snapshots.'},indent=2))
