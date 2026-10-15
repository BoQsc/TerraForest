# SPDX-License-Identifier: 0BSD
"""Check generated cottage access on an exclusive disposable save clone."""
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
    parser.add_argument('--heights', action='store_true')
    parser.add_argument('--actor-doors', action='store_true')
    parser.add_argument('--source', default='combined_enclosed_review')
    parser.add_argument('--expected-doors', type=int, default=4)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,47}', args.source):parser.error('Invalid source slot')
    if args.heights and args.actor_doors:parser.error('Choose one check mode')
    if not 1 <= args.expected_doors <= 64:parser.error('Expected doors must be between 1 and 64')
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    source = worlds / (args.source+'.trw')
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    slot = 'doorwalk_' + uuid.uuid4().hex
    copied = clone_once(worlds, args.source, slot)
    folder = ROOT/'reports/enclosed_settlement_walk'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    fixture = 'actor_door_navigation' if args.actor_doors else 'enclosed_settlement_heights' if args.heights else 'enclosed_settlement_walk'
    command = [config.godot, '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60', '--script', 'res://tests/'+fixture+'.gd', '--', '--world-slot='+slot, '--gameplay-construction', '--ground-cover']
    command.append('--expected-doors='+str(args.expected_doors))
    result = execute(command, folder, 90, 'COMBINED_RESOURCE_ROUTE failures=0')
    unchanged = hashlib.sha256(source.read_bytes()).hexdigest() == before
    (folder/'run.json').write_text(json.dumps(dict(copy=copied, command=command, result=result, source_unchanged=unchanged, **revision_metadata()), indent=2))
    print(('PASS ' if result['passed'] and unchanged else 'FAIL ') + str(folder))
    return 0 if result['passed'] and unchanged else 1

if __name__ == '__main__':raise SystemExit(main())
