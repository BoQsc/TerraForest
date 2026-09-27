"""Verify cross-process leases and kill/reopen behavior against real native archive writes."""
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
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
args=parser.parse_args()
if not args.godot:parser.error('Specify --godot PATH')
engine=Path(args.godot)
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():engine=direct
build=(root/'.build').resolve()
build.mkdir(exist_ok=True)
results=[]
with tempfile.TemporaryDirectory(prefix='archive_recovery_',dir=build) as directory:
    workspace=Path(directory).resolve()
    assert build in workspace.parents
    for trial in range(3):
        path=workspace/f'world_{trial}.tfworld'
        command=[str(engine),'--headless','--path',str(root),'--script','res://tests/archive_process.gd','--',f'--archive-path={path}']
        owner=subprocess.Popen(command+['--archive-mode=writer'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        output=queue.Queue()
        def reader():
            for line in owner.stdout:output.put(line)
        collector=threading.Thread(target=reader,daemon=True)
        collector.start()
        lines=[]
        try:
            deadline=time.monotonic()+30
            ready=False
            while time.monotonic()<deadline and not ready:
                try:line=output.get(timeout=0.25)
                except queue.Empty:
                    if owner.poll() is not None:break
                    continue
                lines.append(line)
                ready='WRITER_READY' in line
            if not ready:raise RuntimeError('Archive writer failed to start: '+''.join(lines)[-5000:])
            probe=subprocess.run(command+['--archive-mode=probe'],capture_output=True,text=True,timeout=20)
            if probe.returncode or 'PROBE_OK' not in probe.stdout:raise RuntimeError(probe.stdout+probe.stderr)
            writing=False
            deadline=time.monotonic()+10
            while time.monotonic()<deadline and owner.poll() is None:
                if list(workspace.glob(path.name+'.pending.*')):
                    writing=True
                    break
                time.sleep(0.001)
            if not writing:raise RuntimeError('No in-progress temporary snapshot observed')
            # The writer is confirmed live and repeatedly publishing snapshots.
            # Force termination, so no destructor or orderly shutdown releases the lease.
            if owner.poll() is not None:raise RuntimeError('Writer exited before the crash test')
            owner.kill()
            owner.wait(timeout=10)
            collector.join(timeout=2)
            owner.stdout.close()
            orphan_count=len(list(workspace.glob(path.name+'.pending.*')))
            verify=subprocess.run(command+['--archive-mode=verify'],capture_output=True,text=True,timeout=20)
            if verify.returncode or 'RECOVERY_OK' not in verify.stdout:raise RuntimeError(verify.stdout+verify.stderr)
            results.append({'trial':trial,'cross_process_lease':True,'temporary_write_observed_before_kill':writing,'canonical_and_backup_valid_after_kill':True,'orphan_temporary_files':orphan_count})
            print(f'PASS crash/reopen trial {trial}; exclusive lease and canonical/backup verified',flush=True)
        finally:
            if owner.poll() is None:
                owner.kill()
                owner.wait(timeout=10)
            collector.join(timeout=2)
            if not owner.stdout.closed:owner.stdout.close()
(root/'reports/archive_process.json').write_text(json.dumps({'failures':0,'trials':results,'scope':'Abrupt process termination during repeated writes; not physical power-loss testing'},indent=2))
