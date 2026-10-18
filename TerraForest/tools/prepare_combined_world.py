# SPDX-License-Identifier: 0BSD
"""Create and verify a furnished gameplay checkpoint without replacing progress."""
import argparse
import datetime
import json
import os
import re
import uuid
from pathlib import Path
from clone_world import clone_once
from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import execute


def prepare(engine, worlds, folder, destination="combined_gameplay", layout="cottages", seed=1703):
    if type(seed) is not int or not 0 <= seed <= 2147483647:
        raise ValueError("Seed must be an integer between 0 and 2147483647")
    if layout not in ('cottages', 'mixed', 'regional', 'poi', 'lakes', 'districts'):
        raise ValueError("Invalid settlement layout")
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,47}', destination):
        raise ValueError("Invalid destination slot")
    worlds.mkdir(parents=True, exist_ok=True)
    if (worlds / (destination + '.trw')).exists():
        print('Existing combined gameplay save retained; nothing regenerated.')
        return 0
    # A second preparation must not race the fixed destination or reports.
    lock = worlds / (destination + '.prepare.lock')
    with lock.open('x') as handle:
        handle.write(str(os.getpid()))
    try:
        slot = 'combined_stage_' + uuid.uuid4().hex
        folder.mkdir(parents=True)
        report = folder / 'checkpoint.json'
        base = [str(engine), '--path', str(ROOT), '--fullscreen', '--resolution',
                '1920x1080', '--max-fps', '60', '--script',
                'res://tools/prepare_combined_world.gd', '--',
                '--world-slot=' + slot, '--world-generator=' + ('13' if layout == 'districts' else '12' if layout == 'lakes' else '11' if layout == 'poi' else '8' if layout == 'regional' else '4'), '--world-seed=' + str(seed),
                '--ground-cover', '--actors', '--vehicle-fleet', '--checkpoint-layout=' + layout, '--checkpoint-report=' + str(report),
                '--derived-cache=user://' + slot]
        metadata = dict(slot=slot, layout=layout, seed=seed, **revision_metadata(), phases=[])
        for phase in ('create', 'reopen'):
            phase_dir = folder / phase
            phase_dir.mkdir()
            command = base + (['--reopen-checkpoint', '--gameplay-construction', '--vehicle-fleet'] if phase == 'reopen' else [])
            print(f'{phase}: preparing the existing settlement workflow at 1920x1080 / cap 60.', flush=True)
            result = execute(command, phase_dir, 540 if layout in ("lakes", "districts") and phase == "create" else 270, 'COMBINED_PREPARATION failures=0')
            metadata['phases'].append(dict(command=command, result=result))
            (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
            if not result['passed']:
                print('Preparation failed; gameplay save not published. Evidence: ' + str(phase_dir))
                return 1
        metadata['publication'] = clone_once(worlds, slot, destination)
        (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
        print('Prepared and reopened slot ' + destination + '. Evidence: ' + str(folder))
        return 0
    finally:
        lock.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--destination', default='combined_gameplay', help='Create only when this save slot is absent')
    parser.add_argument('--layout', choices=('cottages', 'mixed', 'regional', 'poi', 'lakes', 'districts'), default='cottages')
    parser.add_argument('--seed', type=int, default=1703, help='Deterministic new-world seed (0..2147483647); existing saves are preserved')
    parser.add_argument('--status-file', type=Path, help='Optional browser completion status file')
    args = parser.parse_args()
    if not 0 <= args.seed <= 2147483647: parser.error('Seed must be between 0 and 2147483647')
    config, _ = parse_args(['--godot', args.godot] if args.godot else [])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/combined_preparation' / stamp
    def status(state, reason=''):
        if args.status_file is None: return
        value = dict(state=state, slot=args.destination, report=str(folder), reason=reason)
        temporary = args.status_file.with_suffix('.tmp')
        temporary.parent.mkdir(parents=True, exist_ok=True)
        temporary.write_text(json.dumps(value), encoding='utf-8')
        temporary.replace(args.status_file)
    status('running')
    try:
        code = prepare(config.godot, worlds, folder, args.destination, args.layout, args.seed)
    except Exception as error:
        status('failed', str(error))
        raise
    status('ready' if code == 0 else 'failed', '' if code == 0 else 'Generation or save verification failed')
    return code


if __name__ == '__main__':
    raise SystemExit(main())
