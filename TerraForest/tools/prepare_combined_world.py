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


def prepare(engine, worlds, folder, destination="combined_gameplay"):
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
                '--world-slot=' + slot, '--world-generator=4', '--world-seed=1703',
                '--ground-cover', '--checkpoint-report=' + str(report),
                '--derived-cache=user://' + slot]
        metadata = dict(slot=slot, **revision_metadata(), phases=[])
        for phase in ('create', 'reopen'):
            phase_dir = folder / phase
            phase_dir.mkdir()
            command = base + (['--reopen-checkpoint', '--gameplay-construction', '--actors', '--vehicle-fleet'] if phase == 'reopen' else [])
            print(f'{phase}: preparing the existing settlement workflow at 1920x1080 / cap 60.', flush=True)
            result = execute(command, phase_dir, 150, 'COMBINED_PREPARATION failures=0')
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
    args = parser.parse_args()
    config, _ = parse_args(['--godot', args.godot] if args.godot else [])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    return prepare(config.godot, worlds, ROOT / 'reports/combined_preparation' / stamp, args.destination)


if __name__ == '__main__':
    raise SystemExit(main())
