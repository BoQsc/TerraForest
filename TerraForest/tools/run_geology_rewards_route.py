# SPDX-License-Identifier: 0BSD
"""Ore mining check on a fresh copy; never edit the user's gameplay slot."""
import datetime
import argparse
import hashlib
import json
import os
import re
import uuid
from pathlib import Path
from clone_world import clone_once
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--natural', action='store_true', help='Survey and test naturally exposed ore in generator6 caves')
    parser.add_argument('--source', help='Source save copied without modification')
    parser.add_argument('--walk-iron', action='store_true', help='Walk from the saved natural cave entrance to iron; implies --natural')
    args = parser.parse_args()
    if args.walk_iron:args.natural = True
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    source_slot = args.source or ('natural_cave_gameplay' if args.natural else 'geology_gameplay')
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,47}', source_slot):parser.error('Invalid source slot')
    source = worlds / (source_slot + '.trw')
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    slot = ('natural_ore_' if args.natural else 'geology_route_') + uuid.uuid4().hex
    copy = clone_once(worlds, source_slot, slot)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/geology_rewards_route' / stamp
    folder.mkdir(parents=True)
    metadata = dict(copy=copy, phases=[], **revision_metadata())
    passed = True
    if args.natural:
        survey_dir = folder / 'survey'
        survey_dir.mkdir()
        command = [config.godot, '--headless', '--path', str(ROOT), '--script', 'res://tests/natural_ore_survey.gd']
        result = execute(command, survey_dir, 45, 'NATURAL_ORE_SURVEY failures=0')
        metadata['phases'].append(dict(command=command, result=result))
        (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
        if not result['passed']:return 1
    test = 'natural_ore_gameplay' if args.natural else 'geology_rewards_route'
    for phase in ('mine', 'reopen'):
        output = folder / phase
        output.mkdir()
        command = [config.godot, '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080',
                   '--max-fps', '60', '--script', 'res://tests/' + test + '.gd', '--',
                   '--world-slot=' + slot, '--gameplay-construction',
                   '--route-evidence=' + str(folder / 'expected.bin'),
                   *(['--walk-iron'] if args.walk_iron else []),
                   *(['--reopen-route'] if phase == 'reopen' else [])]
        # The walking case includes both descent and return, in addition to startup.
        result = execute(command, output, 120 if args.walk_iron else 90, 'COMBINED_RESOURCE_ROUTE failures=0')
        metadata['phases'].append(dict(command=command, result=result))
        passed = passed and result['passed']
        if not passed:break
    metadata['source_unchanged'] = hashlib.sha256(source.read_bytes()).hexdigest() == before
    (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
    passed = passed and metadata['source_unchanged']
    print(('PASS ' if passed else 'FAIL ') + str(folder))
    return 0 if passed else 1


if __name__ == '__main__':raise SystemExit(main())
