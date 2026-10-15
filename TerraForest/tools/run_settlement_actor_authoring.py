# SPDX-License-Identifier: 0BSD
"""Prepare a disposable, UI-authored settlement actor and verify fresh reopen."""
import argparse
import datetime
import hashlib
import json
import os
import uuid
from pathlib import Path
from clone_world import clone_once
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--play', action='store_true')
    args = parser.parse_args()
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    if args.play and (worlds / 'settlement_actors.trw').exists():
        return play()
    source = worlds / 'combined_gameplay.trw'
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    slot = 'actor_ui_' + uuid.uuid4().hex
    copied = clone_once(worlds, 'combined_gameplay', slot)
    folder = ROOT / 'reports/settlement_actor_authoring' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    command = [config.godot, '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080',
               '--max-fps', '60', '--script', 'res://tests/settlement_actor_authoring.gd', '--',
               '--world-slot=' + slot, '--ground-cover', '--route-evidence=' + str(folder / 'expected')]
    result = execute(command, folder, 65, 'COMBINED_RESOURCE_ROUTE failures=0')
    reopen = None
    if result['passed']:
        reopened = folder / 'reopen'
        reopened.mkdir()
        reopen = execute(command + ['--actors', '--reopen-actors'], reopened, 65, 'COMBINED_RESOURCE_ROUTE failures=0')
    unchanged = hashlib.sha256(source.read_bytes()).hexdigest() == before
    passed = result['passed'] and reopen is not None and reopen['passed'] and unchanged
    metadata = dict(copy=copied, command=command, result=result, reopen=reopen,
                    source_unchanged=unchanged, **revision_metadata())
    if passed and not (worlds / 'settlement_actors.trw').exists():
        metadata['publication'] = clone_once(worlds, slot, 'settlement_actors')
    (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
    print(('PASS ' if passed else 'FAIL ') + str(folder))
    if passed and args.play:
        return play()
    return 0 if passed else 1


def play():
    from run import main as launch
    return launch(['--slot', 'settlement_actors', '--ground-cover', '--actors'])


if __name__ == '__main__':
    raise SystemExit(main())
