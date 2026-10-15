# SPDX-License-Identifier: 0BSD
"""Check generated cottage access on an exclusive disposable save clone."""
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
    source = worlds / 'combined_enclosed_review.trw'
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    slot = 'doorwalk_' + uuid.uuid4().hex
    copied = clone_once(worlds, 'combined_enclosed_review', slot)
    folder = ROOT/'reports/enclosed_settlement_walk'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    command = [config.godot, '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60', '--script', 'res://tests/enclosed_settlement_walk.gd', '--', '--world-slot='+slot, '--gameplay-construction', '--ground-cover']
    result = execute(command, folder, 90, 'COMBINED_RESOURCE_ROUTE failures=0')
    unchanged = hashlib.sha256(source.read_bytes()).hexdigest() == before
    (folder/'run.json').write_text(json.dumps(dict(copy=copied, command=command, result=result, source_unchanged=unchanged, **revision_metadata()), indent=2))
    print(('PASS ' if result['passed'] and unchanged else 'FAIL ') + str(folder))
    return 0 if result['passed'] and unchanged else 1

if __name__ == '__main__':raise SystemExit(main())
