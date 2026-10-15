# SPDX-License-Identifier: 0BSD
"""Extend and drive a copy of the settlement; retain it for inspection."""
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
    parser.add_argument('--play', action='store_true', help='Open the prepared road checkpoint; prepare it first if missing')
    args = parser.parse_args()
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    if args.play and (worlds / 'settlement_travel.trw').exists():
        return play()
    source = worlds / 'combined_gameplay.trw'
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    slot = 'road_trip_' + uuid.uuid4().hex
    copy = clone_once(worlds, 'combined_gameplay', slot)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/settlement_road_trip' / stamp
    folder.mkdir(parents=True)
    command = [config.godot, '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080',
               '--max-fps', '60', '--script', 'res://tests/settlement_road_trip.gd', '--',
               '--world-slot=' + slot, '--ground-cover', '--actors', '--vehicle-fleet',
               '--route-evidence=' + str(folder / 'trip')]
    result = execute(command, folder, 150, 'COMBINED_RESOURCE_ROUTE failures=0')
    reopen = None
    if result['passed']:
        reopen_folder = folder / 'reopen'
        reopen_folder.mkdir()
        reopen = execute(command + ['--reopen-trip'], reopen_folder, 65, 'COMBINED_RESOURCE_ROUTE failures=0')
    unchanged = hashlib.sha256(source.read_bytes()).hexdigest() == before
    passed = result['passed'] and reopen is not None and reopen['passed'] and unchanged
    metadata = dict(copy=copy, slot=slot, command=command, result=result, reopen=reopen,
                    source_unchanged=unchanged, **revision_metadata())
    if passed and not (worlds / 'settlement_travel.trw').exists():
        metadata['publication'] = clone_once(worlds, slot, 'settlement_travel')
    (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
    print(('PASS ' if passed else 'FAIL ') + str(folder))
    if passed and args.play:return play()
    return 0 if passed else 1


def play():
    from run import main as launch
    return launch(['--slot', 'settlement_travel', '--ground-cover', '--actors',
                   '--vehicle-fleet', '--gameplay-construction'])


if __name__ == '__main__':raise SystemExit(main())
