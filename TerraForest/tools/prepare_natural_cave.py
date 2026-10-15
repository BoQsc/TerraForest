# SPDX-License-Identifier: 0BSD
"""Prepare a persistent natural-cave world once, verifying it before publication."""
import datetime
import json
import os
import uuid
from pathlib import Path
from clone_world import clone_once
from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import execute


def prepare(engine, worlds, folder):
    worlds.mkdir(parents=True, exist_ok=True)
    destination = 'natural_cave_gameplay'
    if (worlds / (destination + '.trw')).exists():
        print('Existing natural-cave progress retained.')
        return 0
    lock = worlds / (destination + '.prepare.lock')
    with lock.open('x') as handle:
        handle.write(str(os.getpid()))
    try:
        slot = 'cave_stage_' + uuid.uuid4().hex
        folder.mkdir(parents=True)
        report = folder / 'checkpoint.bin'
        base = [str(engine), '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080',
                '--max-fps', '60', '--script', 'res://tools/prepare_natural_cave.gd', '--',
                '--world-slot=' + slot, '--world-generator=6', '--world-seed=1703',
                '--gameplay-construction', '--ground-cover', '--checkpoint-report=' + str(report),
                '--derived-cache=user://' + slot]
        metadata = dict(slot=slot, phases=[], **revision_metadata())
        for phase in ('create', 'reopen'):
            phase_dir = folder / phase
            phase_dir.mkdir()
            command = base + (['--reopen-checkpoint'] if phase == 'reopen' else [])
            print(phase + ': preparing persistent natural-cave checkpoint.', flush=True)
            result = execute(command, phase_dir, 270, 'NATURAL_CAVE_PREPARATION failures=0')
            metadata['phases'].append(dict(command=command, result=result))
            (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
            if not result['passed']:
                print('Preparation failed; gameplay save not published: ' + str(phase_dir))
                return 1
        metadata['publication'] = clone_once(worlds, slot, destination)
        (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
        print('Verified cave save ready. Evidence: ' + str(folder))
        return 0
    finally:
        lock.unlink()


if __name__ == '__main__':
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    raise SystemExit(prepare(config.godot, worlds, ROOT / 'reports/natural_cave_preparation' / stamp))
