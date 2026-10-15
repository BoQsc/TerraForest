# SPDX-License-Identifier: 0BSD
"""Check opposing actor routes on a disposable copy of the furnished settlement."""
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
    parser.add_argument('--crowd', action='store_true', help='16 active opposing actors with correctness and frame/adapter cost gates')
    args = parser.parse_args()
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    source = worlds / 'combined_gameplay.trw'
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    slot = 'actor_crossing_' + uuid.uuid4().hex
    copied = clone_once(worlds, 'combined_gameplay', slot)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/actor_street_crossing' / stamp
    folder.mkdir(parents=True)
    command = [config.godot, '--path', str(ROOT), '--fullscreen', '--resolution',
               '1920x1080', '--max-fps', '60', '--script',
               'res://tests/actor_street_crossing.gd', '--', '--world-slot=' + slot,
               '--actors', '--ground-cover', '--crossing-output=' + str(folder)]
    if args.crowd:command.append('--crowd')
    result = execute(command, folder, 75, 'ACTOR_STREET_CROSSING failures=0')
    unchanged = hashlib.sha256(source.read_bytes()).hexdigest() == before
    metadata = dict(copy=copied, command=command, result=result,
                    source_unchanged=unchanged, **revision_metadata())
    metadata['native_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in (ROOT / 'addons/world_runtime/bin').glob('*.dll')}
    (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
    print(('PASS ' if result['passed'] and unchanged else 'FAIL ') + str(folder))
    return 0 if result['passed'] and unchanged else 1


if __name__ == '__main__':raise SystemExit(main())
