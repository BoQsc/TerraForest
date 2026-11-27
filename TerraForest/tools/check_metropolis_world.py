# SPDX-License-Identifier: 0BSD
"""Normal metropolis creation, interaction and fresh restore; archive its owned fixture.

--approved-headroom records an explicit maintainer decision for this process only:
256 MiB additional reports and 256 MiB additional owned-world capacity. It does
not change repository limits. Never supply it without that explicit decision.
"""
import argparse
from contextlib import ExitStack
import datetime
import json
import os
from pathlib import Path
import re

import development_storage as storage
from maintain_performance_artifacts import no_game_processes, owned_lease
from retained_artifacts import Store, archive, confined, digest, retire
from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata

CAPTURE_NAMES = {'create_world.png', 'first_play.png', 'trader_world_trade.png',
                 'trader_world_counter.png', 'grand_cathedral_generated_crypt.png',
                 'expected_player.bin', 'expected_stock.bin'}
CAPTURE_NAMES.update(kind + '_' + view + '.png'
                     for kind in ('trader_t1', 'town_hall_t1', 'church_c1', 'school_s2', 'warehouse_w1')
                     for view in ('street_final', 'overview_final', 'basement_final'))
CAPTURE_NAMES.update(kind + '_generated_' + view + '.png'
                     for kind in ('grand_cathedral', 'courtyard_flats', 'street_tower')
                     for view in ('street', 'overview'))
CAPTURE_NAMES.update('metropolis_bridge_' + str(index) + '.png' for index in range(3))

def retire_fixture(folder, record, completion_name='run.json'):
    """Exact creation receipts only; changed or linked outputs remain untouched."""
    no_game_processes()
    if completion_name not in ('run.json', 'recheck.json'):
        raise ValueError('Unrecognized completed driver receipt')
    completion = folder / completion_name
    if json.dumps(json.loads(completion.read_text()), sort_keys=True) != json.dumps(record, sort_keys=True):
        raise ValueError('Completed driver receipt disagrees with retirement request')
    request_path = folder / 'request.json'
    if not request_path.is_file():
        return {'pending': False, 'reason': 'No generation request was created'}
    request = json.loads(request_path.read_text())
    slot = request.get('slot', '')
    if not re.fullmatch(r'Metropolis_1703_[0-9a-f]{8}', slot):
        raise ValueError('Invalid owned metropolis identity')
    userdata = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest'
    status_name = request.get('status', '')
    status_path = userdata / status_name[7:] if status_name.startswith('user://') else Path(status_name)
    status_path = confined(status_path, userdata)
    state = json.loads(status_path.read_text())
    first = record.get('phases', [{}])[0]
    command = first.get('command', [])
    if (record.get('purpose') != 'normal metropolis generation and fresh restore' or
            'passed' not in record or first.get('phase') != 'create' or
            first.get('result', {}).get('exit_code') is None or
            '--script' not in command or command[command.index('--script')+1] != 'res://tests/production_buildings.gd' or
            '--metropolis' not in command or '--metropolis-evidence='+folder.as_posix() not in command):
        raise ValueError('Completed metropolis driver ownership is missing')
    pid = first.get('result', {}).get('pid')
    if request.get('pid') != pid or state.get('coordinator_pid') != pid or state.get('slot') != slot:
        raise ValueError('Generation process ownership disagrees')
    generation = confined(Path(state['report']), userdata / 'generation_reports')
    metadata = json.loads((generation / 'run.json').read_text())
    stage = state.get('staging_slot', '')
    if (not re.fullmatch(r'combined_stage_[0-9a-f]{32}', stage) or
            generation.name != stage.removeprefix('combined_stage_') or
            metadata.get('stage') != stage or metadata.get('destination') != slot):
        raise ValueError('Staging creation receipt disagrees')
    published = bool(metadata.get('publication', {}).get('ok') and metadata.get('publication', {}).get('created'))
    worlds = userdata / 'worlds'
    confined(worlds, worlds)
    slots = [stage] + ([slot] if published else [])
    cutoff = completion.stat().st_mtime_ns + 2_000_000_000
    members = []
    for owned in slots:
        for source in worlds.glob(owned + '.*'):
            if source.name == owned + '.trw.lock':
                continue
            confined(source, worlds)
            for path in source.rglob('*') if source.is_dir() else [source]:
                if path.is_file() and path.stat().st_mtime_ns > cutoff:
                    raise ValueError('Fixture changed after its completed run; retained')
            members.append(source.name)
    # Include failed native staging in accounting before any archive allocation.
    registry = ROOT / 'reports/artifact_retention/owned_worlds.json'
    registry.parent.mkdir(parents=True, exist_ok=True)
    with storage.lease(registry):
        registered = json.loads(registry.read_text()) if registry.exists() else {}
        for owned in slots:
            registered[owned] = {'last_report': folder.relative_to(ROOT).as_posix()}
        pending = registry.with_suffix('.pending')
        pending.write_text(json.dumps(registered, indent=2)); pending.replace(registry)
    storage.admit(ROOT, report_bytes=2*2**20, world_bytes=0)
    (ROOT / 'reports/retained_artifacts').mkdir(parents=True, exist_ok=True)
    with owned_lease(ROOT / 'reports/retained_artifacts/writer', ROOT), ExitStack() as locks:
        for owned in slots:
            locks.enter_context(owned_lease(worlds / (owned + '.trw'), worlds))
        store = Store(ROOT / 'reports/retained_artifacts/chunks')
        output = folder / 'world.archive.json'
        saved = archive(worlds, sorted(members), output, store,
                        {'kind': 'metropolis-production-fixture', 'request_sha256': digest(request_path),
                         'generation_sha256': digest(generation / 'run.json'),
                         'run_sha256': digest(completion)})
        removed = retire(saved, store, worlds)
    return {'pending': False, 'manifest': str(output), 'retired_bytes': removed, 'slots': slots}



def retain_captures():
    completed = []
    for receipt in sorted((ROOT / 'reports/metropolis_world').glob('*/run.json')):
        record = json.loads(receipt.read_text())
        if record.get('purpose') != 'normal metropolis generation and fresh restore' or 'passed' not in record:
            continue
        folder = confined(receipt.parent, ROOT / 'reports/metropolis_world')
        if any((folder / pin).exists() for pin in ('.retain', 'RETAIN_READY', 'captures.archive.json')):
            continue
        members = sorted(p.relative_to(folder).as_posix() for p in folder.rglob('*')
                         if p.is_file() and p.name in CAPTURE_NAMES)
        if members:
            completed.append((folder, members))
    if len(completed) <= 2:
        return []
    no_game_processes()
    manifests = []
    (ROOT / 'reports/retained_artifacts').mkdir(parents=True, exist_ok=True)
    with owned_lease(ROOT / 'reports/retained_artifacts/writer', ROOT):
        store = Store(ROOT / 'reports/retained_artifacts/chunks')
        for folder, members in completed[:-2]:
            no_game_processes()
            output = folder / 'captures.archive.json'
            saved = archive(folder, members, output, store,
                            {'kind': 'metropolis-production-captures', 'run_sha256': digest(folder / 'run.json')})
            retire(saved, store, folder)
            manifests.append(str(output))
    return manifests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--approved-headroom', action='store_true')
    parser.add_argument('--archive-only', type=Path)
    parser.add_argument('--completion', choices=('run.json', 'recheck.json'), default='run.json')
    args = parser.parse_args()
    baseline = dict(storage.LIMITS)
    if args.approved_headroom:
        storage.LIMITS['reports'] += 256 * 2**20
        storage.LIMITS['owned_worlds'] += 256 * 2**20
    allocation = dict(report_bytes=160 * 2**20, world_bytes=224 * 2**20)
    if args.dry_run:
        try:
            admission = storage.admit(ROOT, **allocation)
            print(json.dumps({'admitted': True, 'planned': allocation, 'limits': admission['limits']}))
        except OSError as error:
            print(json.dumps({'admitted': False, 'planned': allocation, 'reason': str(error)}))
        return 0
    if args.archive_only:
        folder = confined(args.archive_only.resolve(), ROOT / 'reports/metropolis_world')
        record = json.loads((folder / args.completion).read_text())
        result = retire_fixture(folder, record, args.completion)
        retention_name = 'recheck_retention.json' if args.completion == 'recheck.json' else 'retention.json'
        (folder / retention_name).write_text(json.dumps(result, indent=2))
        print(json.dumps(result))
        return int(result.get('pending', False))
    no_game_processes()
    retain_captures()
    admission = storage.admit(ROOT, **allocation)
    engine = parse_args(['--godot', args.godot] if args.godot else [])[0].godot
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/metropolis_world' / stamp
    folder.mkdir(parents=True)
    record = {**revision_metadata(), 'purpose': 'normal metropolis generation and fresh restore',
              'test_sha256': digest(ROOT / 'tests/production_buildings.gd'),
              'native_sha256': {p.relative_to(ROOT).as_posix(): digest(p)
                                for p in sorted((ROOT / 'addons').glob('*/bin/*.dll'))},
              'baseline_limits': baseline, 'approved_headroom': args.approved_headroom,
              'admission': admission, 'phases': []}
    shared = ['--metropolis', '--metropolis-evidence=' + folder.as_posix(),
              '--session-evidence-dir=' + folder.as_posix(), '--isolated-render']
    for name, extra in [('create', ['--create-production']), ('interact', []), ('restore', ['--restore-production'])]:
        phase = folder / name
        phase.mkdir()
        command = [str(engine), '--path', str(ROOT), '--windowed', '--resolution', '1920x1080',
                   '--max-fps', '60', '--log-file', str(phase / 'engine.log'), '--script',
                   'res://tests/production_buildings.gd', '--', *shared, *extra]
        result = execute(command, phase, 600, 'PRODUCTION_BUILDINGS checks=', isolated_render=True)
        record['phases'].append({'phase': name, 'command': command, 'result': result})
        (folder / 'run.json').write_text(json.dumps(record, indent=2))
        storage.register_worlds(command, phase)
        print(('PASS ' if result['passed'] else 'FAIL ') + name, flush=True)
        if not result['passed']:
            break
    record['passed'] = len(record['phases']) == 3 and all(p['result']['passed'] for p in record['phases'])
    (folder / 'run.json').write_text(json.dumps(record, indent=2))
    try:
        retention = retire_fixture(folder, record)
    except (OSError, ValueError) as error:
        retention = {'pending': True, 'reason': str(error), 'retry': 'Use --archive-only with this exact report'}
    (folder / 'retention.json').write_text(json.dumps(retention, indent=2))
    try:
        retain_captures()
    except OSError as error:
        print('Capture retention pending:', str(error))
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder))
    print('Fixture retention:', json.dumps(retention))
    return int(not record['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
