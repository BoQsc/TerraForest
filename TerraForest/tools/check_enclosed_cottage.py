# SPDX-License-Identifier: 0BSD
"""Check building interaction and disk reopen in a unique clone, never the source."""
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
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    source = worlds / 'combined_gameplay.trw'
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    slot = 'doors_' + uuid.uuid4().hex
    copied = clone_once(worlds, 'combined_gameplay', slot)
    folder = ROOT / 'reports/enclosed_cottage' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    command = [config.godot, '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60',
               '--script', 'res://tests/enclosed_cottage.gd', '--', '--world-slot=' + slot,
               '--route-evidence=' + str(folder / 'expected')]
    result = execute(command, folder, 65, 'COMBINED_RESOURCE_ROUTE failures=0')
    reopen = None
    if result['passed']:
        reopened = folder / 'reopen'; reopened.mkdir()
        reopen = execute(command + ['--reopen-building'], reopened, 65, 'COMBINED_RESOURCE_ROUTE failures=0')
    unchanged = hashlib.sha256(source.read_bytes()).hexdigest() == before
    passed = result['passed'] and reopen is not None and reopen['passed'] and unchanged
    (folder / 'run.json').write_text(json.dumps(dict(copy=copied, command=command, result=result, reopen=reopen,
        source_unchanged=unchanged, **revision_metadata()), indent=2))
    print(('PASS ' if passed else 'FAIL ') + str(folder))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
