# SPDX-License-Identifier: 0BSD
"""Reuse an unretired, receipt-owned regional publication for interaction QA.

Allocates no world, source copy or export. Admits 160 MiB for captures/receipts;
successful completion cold-retires the exact fixture. Failed rechecks keep the
one existing fixture ready for a correction. Original failed receipts stay intact.
--approved-headroom uses the same explicit, process-local QA decision as creation.
"""
import argparse
import datetime
import json
import os
from pathlib import Path

import check_metropolis_world as creation
from retained_artifacts import confined, digest


def validated_creation(folder, original, family, diagnostic_exit_warning=False):
    """Allow only this family's completed creation; never mutate human fixtures."""
    if original.get('human_playtest_owned') or any((folder / pin).exists() for pin in ('.retain', 'RETAIN_READY')):
        raise ValueError('Protected human/review fixture cannot be used for mutating QA')
    phases = original.get('phases', [])
    first = dict(phases[0]) if phases else {}
    if original.get('purpose') != creation.REPORT_FAMILIES[family] or first.get('phase') != 'create':
        raise ValueError('Recheck requires a matching ordinary creation receipt')
    result = first.get('result', {})
    cleanup_only = diagnostic_exit_warning and creation.zero_reference_exit_only(result, folder / 'create')
    if not result.get('passed') and not cleanup_only:
        raise ValueError('Recheck requires passed creation or the verified diagnostic cleanup exception')
    first['cleanup_warning_only'] = cleanup_only
    return first


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--approved-headroom', action='store_true')
    parser.add_argument('--restore-only', action='store_true', help='Reuse a passed interaction with identical test/native inputs')
    parser.add_argument('--diagnostic-exit-warning', action='store_true', help='Continue only after the recorded zero-reference cleanup warning; strict failure remains')
    args = parser.parse_args()
    creation.no_game_processes()
    candidate = args.evidence.resolve()
    family = candidate.parent.name
    if family not in creation.REPORT_FAMILIES: raise ValueError('Unknown regional QA family')
    folder = confined(candidate, creation.ROOT / 'reports' / family)
    if (folder / 'world.archive.json').exists():
        raise ValueError('Fixture is cold-retired; never recreate it under its old identity')
    original = json.loads((folder / 'run.json').read_text())
    first = validated_creation(folder, original, family, args.diagnostic_exit_warning)
    request = json.loads((folder / 'request.json').read_text())
    published = json.loads((folder / 'world.json').read_text())
    userdata = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest'
    status = request['status']
    state = json.loads(confined(userdata / status[7:] if status.startswith('user://') else Path(status), userdata).read_text())
    generation = confined(Path(state['report']), userdata / 'generation_reports')
    metadata = json.loads((generation / 'run.json').read_text())
    if (request.get('pid') != first['result'].get('pid')
            or state.get('coordinator_pid') != request['pid']
            or published.get('slot') != request.get('slot') or not published.get('created')
            or metadata.get('destination') != request['slot']
            or not metadata.get('publication', {}).get('created')
            or not metadata.get('publication', {}).get('ok')):
        raise ValueError('Published fixture ownership disagrees')
    native = {p.relative_to(creation.ROOT).as_posix(): digest(p)
              for p in sorted((creation.ROOT / 'addons').glob('*/bin/*.dll'))}
    inputs = json.loads((folder / 'verification_inputs.json').read_text())
    if inputs['native_sha256'] != native:
        raise ValueError('Native inputs changed; the old publication is not this fixture')
    interaction = None
    previous_path = folder / 'recheck.json'
    if not previous_path.exists():
        previous_path = folder / 'run.json'
    if args.restore_only:
        previous = json.loads(previous_path.read_text())
        phases = previous.get('phases', [])
        if (previous.get('test_sha256') != digest(creation.ROOT / 'tests/production_buildings.gd')
                or previous.get('native_sha256') != native or len(phases) < 2
                or phases[1].get('phase') != 'interact' or not phases[1].get('result', {}).get('passed')):
            raise ValueError('No matching passed interaction is available for reuse')
        interaction = phases[1]
    if args.approved_headroom:
        creation.storage.LIMITS['reports'] += 256 * 2**20
        creation.storage.LIMITS['owned_worlds'] += 256 * 2**20
    admission = creation.storage.admit(creation.ROOT, report_bytes=(16 if args.restore_only else 160)*2**20, world_bytes=0)
    stamp = 'recheck_' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    # Keep the earlier failed run's tiny inventory evidence as well as its images.
    for name in ('expected_player.bin', 'expected_stock.bin', 'lake_view.json'):
        path = folder / name
        if path.exists():
            destination = folder / stamp / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(path.read_bytes())
    engine = creation.parse_args([])[0].godot
    record = {**creation.revision_metadata(), 'purpose': original['purpose'],
              'creation_run_sha256': digest(folder / 'run.json'), 'creation_reused': True,
              'test_sha256': digest(creation.ROOT / 'tests/production_buildings.gd'),
              'native_sha256': native, 'admission': admission,
              'approved_headroom': args.approved_headroom, 'capture_prefix': stamp,
              'phases': [first]}
    if interaction is not None:
        record['interaction_reused_from_sha256'] = digest(previous_path)
        record['phases'].append(interaction)
    frozen = folder / stamp / 'run.json'
    frozen.parent.mkdir(parents=True, exist_ok=True)
    for name, extra in [('interact', []), ('restore', ['--restore-production'])]:
        if name == 'interact' and interaction is not None:
            continue
        phase = folder / (stamp + '_' + name)
        phase.mkdir()
        command = [str(engine), '--verbose', '--path', str(creation.ROOT), '--windowed', '--resolution', '1920x1080',
                   '--max-fps', '60', '--log-file', str(phase / 'engine.log'), '--script',
                   'res://tests/production_buildings.gd', '--', '--metropolis',
                   '--metropolis-evidence=' + folder.as_posix(),
                   '--session-evidence-dir=' + folder.as_posix(), '--isolated-render',
                   '--metropolis-capture-prefix=' + stamp, *extra]
        if family == 'inhabited_island_world': command.append('--inhabited-island')
        result = creation.execute(command, phase, 600, 'PRODUCTION_BUILDINGS checks=', isolated_render=True)
        cleanup_only = args.diagnostic_exit_warning and creation.zero_reference_exit_only(result, phase)
        record['phases'].append({'phase': name, 'command': command, 'result': result, 'cleanup_warning_only': cleanup_only})
        creation.storage.register_worlds(command, phase)
        (folder / 'recheck.json').write_text(json.dumps(record, indent=2))
        frozen.write_text(json.dumps(record, indent=2))
        print(('PASS ' if result['passed'] else 'FAIL ') + name, flush=True)
        if not result['passed'] and not cleanup_only:
            break
    record['passed'] = len(record['phases']) == 3 and all(p['result']['passed'] for p in record['phases'])
    record['functional_passed'] = len(record['phases']) == 3 and all(p['result']['passed'] or p.get('cleanup_warning_only') for p in record['phases'])
    (folder / 'recheck.json').write_text(json.dumps(record, indent=2))
    frozen.write_text(json.dumps(record, indent=2))
    retention = {'pending': True, 'reason': 'Failed recheck retains this same fixture for correction'}
    if record['functional_passed']:
        try:
            retention = creation.retire_fixture(folder, record, 'recheck.json')
        except (OSError, ValueError) as error:
            retention = {'pending': True, 'reason': str(error)}
    (folder / 'recheck_retention.json').write_text(json.dumps(retention, indent=2))
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder / 'recheck.json'))
    print('Fixture retention:', json.dumps(retention))
    return int(not record['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
