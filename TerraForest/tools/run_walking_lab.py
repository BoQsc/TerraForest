# SPDX-License-Identifier: 0BSD
"""Bounded source gameplay performance lab; no export, clone or saved-world write."""
import argparse
import datetime
import json
import subprocess
import uuid
from pathlib import Path

from analyze_walking_performance import analyze, read_run
from development_storage import admit
from maintain_homestead_captures import candidates, no_game_processes, owned_lease
from play_checkpoint import revision_metadata
from retained_artifacts import Store, archive, retire, digest
from run import ROOT, parse_args
from run_godot_check import command_for, execute
from run_vegetation_lab import active_render_jobs


def retain():
    selected = [(folder, members) for folder, members in candidates()
                if 'walking_performance.gd' in members]
    if not selected:
        return []
    no_game_processes()
    result = []
    with owned_lease(ROOT/'reports/retained_artifacts/writer', ROOT):
        store = Store(ROOT/'reports/retained_artifacts/chunks')
        for folder, members in selected:
            no_game_processes()
            record = archive(folder, list(members), folder/'homestead.archive.json', store,
                             dict(kind='completed-object-check-captures', run_sha256=digest(folder/'run.json')))
            result.append({'manifest': str(folder/'homestead.archive.json'), 'retired_bytes': retire(record, store, folder)})
    return result


def identity():
    paths = subprocess.check_output(['git','ls-files','-z'], cwd=ROOT).decode().split('\0')
    suffixes = {'.gd','.gdshader','.gdshaderinc','.cpp','.h','.hpp','.dll','.godot','.tscn','.tres'}
    return {name: digest(ROOT/name) for name in paths if Path(name).suffix in suffixes and (ROOT/name).is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--source', default='Homestead_Valley')
    parser.add_argument('--seconds', type=int, default=30, choices=range(30,121))
    parser.add_argument('--diagnostic', action='store_true')
    parser.add_argument('--render-control', action='store_true')
    parser.add_argument('--mesh-cache-control', action='store_true')
    parser.add_argument('--pacing', choices=['uncapped','cap61'], default='uncapped')
    args = parser.parse_args()
    jobs = active_render_jobs()
    if jobs:
        raise RuntimeError('Timing requires idle game/build jobs: '+json.dumps(jobs))
    retain()
    # Reserve output before allocating the owning receipt. No new world/scratch.
    admission = admit(ROOT, report_bytes=2*2**20, world_bytes=0)
    config, _ = parse_args(['--godot',args.godot] if args.godot else [])
    engine = Path(config.godot).resolve()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT/'reports/checks'/stamp
    extra = ['--gameplay-source-slot='+args.source,'--lab-seconds='+str(args.seconds),
             '--lab-pacing='+args.pacing,'--lab-run-id='+uuid.uuid4().hex]
    if args.diagnostic:
        extra.append('--lab-diagnostic')
    if args.render_control:
        extra.append('--lab-render-control')
    if args.mesh_cache_control:
        extra.append('--lab-mesh-cache-control')
    command, cache = command_for(engine,'walking_performance',folder,extra,headless=False)
    command[command.index('--fullscreen')] = '--windowed'
    command.append('--isolated-render')
    before = identity()
    folder.mkdir(parents=True)
    (folder/'source_identity.json').write_text(json.dumps(before, sort_keys=True)+'\n')
    source = ROOT/'tests/walking_performance.gd'
    (folder/'walking_performance.gd').write_bytes(source.read_bytes())
    record = dict(command=command, cache=cache, utc=stamp, isolated_render=True,
                  admission=admission, engine_sha256=digest(engine), test_sha256=digest(source),
                  source_identity_sha256=digest(folder/'source_identity.json'), **revision_metadata())
    record['tool_sha256'] = {name: digest(ROOT/'tools'/name) for name in
                            ('run_walking_lab.py','analyze_walking_performance.py','run_godot_check.py')}
    receipt = folder/'run.json'
    receipt.write_text(json.dumps(record, indent=2)+'\n')
    print('WALKING_LAB '+str(folder), flush=True)
    record['result'] = execute(command, folder, 360, 'WALKING_LAB_COMPLETE', isolated_render=True)
    after = identity()
    record['source_unchanged'] = before == after and record['test_sha256'] == digest(source)
    record['jobs_after'] = active_render_jobs()
    receipt.write_text(json.dumps(record, indent=2)+'\n')
    if (folder/'walking.json').is_file():
        meta, rows = read_run(folder)
        result = analyze(meta, rows)
        result['engine_check_passed'] = record['result']['passed']
        (folder/'walking_analysis.json').write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps({k:result[k] for k in ('valid','frames','cadence_ms','critical_frames','capacity_qualification_pass')}), flush=True)
    else:
        result = {'valid': False, 'capacity_qualification_pass': False}
    # Only this family's completed receipts; retain two ready, preserve pins.
    record['retention_after'] = retain()
    receipt.write_text(json.dumps(record, indent=2)+'\n')
    return 0 if result['capacity_qualification_pass'] else (2 if result['valid'] else 1)


if __name__ == '__main__':
    raise SystemExit(main())
