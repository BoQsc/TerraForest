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
from build_startup_index import build as startup_index, TARGET as INDEX


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def generated_content(report):
    """Compare authored content; exclude only known observation timings/counters."""
    report = Path(report)
    def without_times(value):
        if isinstance(value, dict):
            return {k:without_times(v) for k,v in value.items() if k not in ('elapsed_us','capture_us','scene_us')}
        if isinstance(value, list):
            return [without_times(v) for v in value]
        return value
    names = ['building_parking','container_locks','door_reinforcement','exploration',
             'house_lights','house_sleepers','location_originals']
    result = {name:without_times(read(report/(name+'.json'))) for name in names}
    plan = read(report/'generation_plan_identity.json')
    result['plan'] = {key:plan[key] for key in ('version','seed','generator','digest','options')}
    water = read(report/'generated_lakes_bake.json')
    result['generated_water'] = {k:v for k,v in water.items() if k not in ('milliseconds','steps')}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', choices=['before', 'after'], required=True)
    parser.add_argument('--compare', type=Path)
    parser.add_argument('--family', choices=['outdoor','planning'], default='outdoor')
    args = parser.parse_args()
    if args.family=='planning' and not args.compare:
        parser.error('Planning comparison requires an existing baseline receipt')
    if INDEX.read_text(encoding='utf-8')!=startup_index():
        parser.error('Refresh the dependency index with tools/build_startup_index.py before benchmarking')
    retention = maintain(apply=True, keep=2)
    if retention['errors']:
        raise RuntimeError('Retention failed: ' + str(retention['receipt']))
    admission = admit(report_bytes=12*2**20, world_bytes=128*2**20, scratch_bytes=0)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/startup_optimization' / (args.family + '_' + args.label + '_' + stamp)
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
    if args.family=='planning':
        record['planning_sources'] = {}
        for name in ('custom_world_plan','generate_world_task','startup_resources'):
            path=ROOT/'addons/world_runtime'/(name+'.gd')
            record['planning_sources'][name]=hashlib.sha256(path.read_bytes()).hexdigest()
            (folder/(name+'.gd.txt')).write_bytes(path.read_bytes())
        record['planning_sources']['startup_index']=hashlib.sha256(INDEX.read_bytes()).hexdigest()
        (folder/'startup_index.benchmark.json').write_bytes(INDEX.read_bytes())
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
            result['planning_seconds'] = next(t['microseconds']/1e6 for t in result['stages'] if t['stage']=='Planning terrain, streets and building sites')
            result['initialization_seconds'] = next(t['microseconds']/1e6 for t in result['stages'] if t['stage']=='Initializing generated terrain data')
            result['objects'] = len(outdoors['placements'])
            if args.compare:
                before = read(args.compare/'outdoor_objects.json')
                result['placements_identical'] = before['placements']==outdoors['placements']
                result['skipped_identical'] = before['skipped']==outdoors['skipped']
                result['passed'] = result['passed'] and result['placements_identical'] and result['skipped_identical']
                result['comparison'] = str(args.compare.resolve())
                if args.family=='planning':
                    previous=read(args.compare/'run.json')['result']['generation_report']
                    before_content=generated_content(previous)
                    after_content=generated_content(report)
                    result['generated_content_matches']={k:before_content[k]==after_content[k] for k in before_content}
                    result['passed']=result['passed'] and all(result['generated_content_matches'].values())
                    (folder/'generated_content.json').write_text(json.dumps(after_content,indent=2)+'\n')
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
