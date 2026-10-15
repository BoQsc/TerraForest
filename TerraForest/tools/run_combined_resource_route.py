# SPDX-License-Identifier: 0BSD
"""Gather/build/store check on a fresh copy; never edit the user's gameplay slot."""
import datetime
import argparse
import re
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
    parser.add_argument('--source', default='combined_gameplay')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,47}', args.source):parser.error('Invalid source slot')
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    source = worlds / (args.source + '.trw')
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    slot = 'combined_route_' + uuid.uuid4().hex
    copy = clone_once(worlds, args.source, slot)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/combined_resource_route' / stamp
    folder.mkdir(parents=True)
    metadata = dict(copy=copy, phases=[], **revision_metadata())
    passed = True
    for phase in ('route', 'travel', 'reopen'):
        output = folder / phase
        output.mkdir()
        command = [config.godot, '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080',
                   '--max-fps', '60', '--script', ('res://tests/combined_travel_route.gd' if phase == 'travel' else 'res://tests/combined_resource_route.gd'), '--',
                   '--world-slot=' + slot, '--gameplay-construction', '--ground-cover', '--actors',
                   '--vehicle-fleet', '--route-evidence=' + str(folder / 'expected.bin'),
                   *(['--reopen-route'] if phase == 'reopen' else [])]
        result = execute(command, output, 90, 'COMBINED_RESOURCE_ROUTE failures=0')
        metadata['phases'].append(dict(command=command, result=result))
        passed = passed and result['passed']
        if not passed:break
    metadata['source_unchanged'] = hashlib.sha256(source.read_bytes()).hexdigest() == before
    (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
    passed = passed and metadata['source_unchanged']
    print(('PASS ' if passed else 'FAIL ') + str(folder))
    return 0 if passed else 1


if __name__ == '__main__':raise SystemExit(main())
