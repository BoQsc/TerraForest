# SPDX-License-Identifier: 0BSD
"""Time the complete source launch; preserve OS caches and never open a world."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import time

from development_storage import ROOT, admit
from isolated_render_process import IsolatedRenderProcess
from maintain_homestead_captures import maintain


def run(folder, force=False, timeout=300):
    folder.mkdir(parents=True, exist_ok=False)
    command = [str(ROOT / 'TerraForest.exe'), '--path', str(ROOT.parent / 'Launcher'),
               '--log-file', str(folder / 'launcher.log'), '--script', 'res://tests/full_launch.gd',
               '--', '--temporary', '--check-evidence-dir=' + str(folder)]
    if force:
        command.append('--force-prepare')
    command.append('--launch-start-unix-usec=' + str(time.time_ns() // 1000))
    started = time.perf_counter()
    timed_out = False
    with (folder / 'console.log').open('w', encoding='utf-8') as output:
        process = IsolatedRenderProcess(command, cwd=ROOT, stdout=output)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            # This exact PID and its children belong to this admitted run.
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True, check=True)
            code = process.wait(timeout=10)
        finally:
            process.close()
    elapsed = time.perf_counter() - started
    metrics_path = folder / 'first_ui.json'
    metrics = json.loads(metrics_path.read_text()) if metrics_path.exists() else {}
    logs = '\n'.join(path.read_text(encoding='utf-8', errors='replace') for path in folder.glob('*.log'))
    errors = [line for line in logs.splitlines() if 'ERROR:' in line or 'FAIL ' in line or 'leaked at exit' in line]
    passed = code == 0 and not timed_out and not errors and metrics.get('failures') == 0
    return {'command': command, 'cache_state': 'Fresh processes; retained source imports and Windows/driver caches.',
            'result': {'exit_code': code, 'passed': passed, 'timed_out': timed_out,
                       'elapsed_seconds': elapsed, 'diagnostics': errors}, 'metrics': metrics}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--force-prepare', action='store_true', help='Ignore a current preparation record; rebuild/import only where required')
    args = parser.parse_args()
    admission = admit(ROOT, report_bytes=16 * 2**20, world_bytes=0)
    maintain(apply=True)
    folder = ROOT / 'reports/checks' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    result = run(folder, args.force_prepare)
    result['admission'] = admission
    (folder / 'run.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    maintain(apply=True)
    print(('PASS ' if result['result']['passed'] else 'FAIL ') + str(folder))
    print(json.dumps(result['metrics']))
    return 0 if result['result']['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
