# SPDX-License-Identifier: 0BSD
"""Compare ordinary furnished-world generation; retain two owned startup fixtures."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

from development_storage import ROOT, admit, register_worlds
from isolated_render_process import IsolatedRenderProcess
from maintain_performance_artifacts import maintain
from resource_limits import ResourceMonitor


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', choices=['before', 'after'], required=True)
    parser.add_argument('--compare', type=Path)
    args = parser.parse_args()
    retention = maintain(apply=True, keep=2)
    if retention['errors']:
        raise RuntimeError('Retention failed: ' + str(retention['receipt']))
    admission = admit(report_bytes=12*2**20, world_bytes=128*2**20, scratch_bytes=0)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/startup_optimization' / ('outdoor_' + args.label + '_' + stamp)
    folder.mkdir(parents=True, exist_ok=False)
    slot = 'StartupBench_' + uuid.uuid4().hex[:16]
    command = [str(ROOT/'TerraForest.exe'), '--path', str(ROOT), '--windowed',
               '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(folder/'engine.log'),
               '--script', 'res://tests/startup_benchmark.gd', '--', '--benchmark-generate',
               '--benchmark-output=' + str(folder), '--benchmark-slot=' + slot]
    source = ROOT/'addons/structures/outdoor_generation.gd'
    record = {'command': command, 'slot': slot, 'label': args.label, 'admission': admission,
              'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'driver_sha256': hashlib.sha256((ROOT/'tests/startup_benchmark.gd').read_bytes()).hexdigest(),
              'cache_scope': 'Retained OS/import/plan/derived caches; fresh process, ordinary default browser recipe.',
              'lifecycle': 'Existing startup retention keeps two ready owned worlds; verified archives preserve older fixtures. Small logs/JSON/one ready image remain with receipts; no export or source-tree copy.'}
    (folder/'outdoor_source.gd.txt').write_bytes(source.read_bytes())
    (folder/'run.json').write_text(json.dumps(record, indent=2)+'\n')
    register_worlds(command, folder)
    print('OUTDOOR_BENCHMARK ' + str(folder), flush=True)
    began = time.perf_counter()
    result = {'timed_out': False}
    with (folder/'console.log').open('w', encoding='utf-8') as output:
        process = IsolatedRenderProcess(command, cwd=ROOT, stdout=output)
        monitor = ResourceMonitor(process.pid)
        try:
            while process.poll() is None:
                monitor.sample()
                if time.perf_counter()-began > 660:
                    result['timed_out'] = True
                    process.kill()
                    break
                try:
                    process.wait(timeout=.25)
                except subprocess.TimeoutExpired:
                    pass
            result['exit_code'] = process.wait()
            result['resources'] = monitor.report()
        finally:
            if process.poll() is None:
                process.kill(); process.wait()
            monitor.close(); process.close()
    result['elapsed_seconds'] = time.perf_counter()-began
    logs = (folder/'console.log').read_text(encoding='utf-8', errors='replace')
    result['errors'] = re.findall(r'(?m)^\s*(?:SCRIPT ERROR:|ERROR:|FAIL\b|WARNING:.*leaked)[^\r\n]*', logs)
    result['passed'] = result['exit_code']==0 and not result['timed_out'] and not result['errors'] and 'STARTUP_BENCHMARK ok=true' in logs
    if (folder/'result.json').exists():
        metrics = read(folder/'result.json')
        result['first_ready_seconds'] = metrics['first_ready_ms']/1000
        if metrics.get('generation', {}).get('report'):
            report = Path(metrics['generation']['report'])
            generation = read(report/'run.json')
            outdoors = read(report/'outdoor_objects.json')
            (folder/'outdoor_objects.json').write_text(json.dumps(outdoors, indent=2)+'\n')
            result['generation_report'] = str(report)
            result['stages'] = generation['phases'][0]['profile']['timings']
            result['creating_seconds'] = generation['phases'][0]['elapsed_usec']/1e6
            result['outdoor_seconds'] = next(t['microseconds']/1e6 for t in result['stages'] if t['stage'].startswith('Placing outdoor storage'))
            result['objects'] = len(outdoors['placements'])
            if args.compare:
                before = read(args.compare/'outdoor_objects.json')
                result['placements_identical'] = before['placements']==outdoors['placements']
                result['skipped_identical'] = before['skipped']==outdoors['skipped']
                result['passed'] = result['passed'] and result['placements_identical'] and result['skipped_identical']
                result['comparison'] = str(args.compare.resolve())
    record['result'] = result
    (folder/'run.json').write_text(json.dumps(record, indent=2)+'\n')
    worlds = Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
    if (worlds/(slot+'.trw')).exists():
        (worlds/(slot+'.diagnostic.json')).write_text(json.dumps({'diagnostic': True, 'source': str(folder/'run.json')})+'\n')
    retention = maintain(apply=True, keep=2)
    print(json.dumps({k:v for k,v in result.items() if k not in ('resources','stages')}, indent=2), flush=True)
    if retention['errors'] or not result['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
