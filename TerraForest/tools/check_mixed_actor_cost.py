# SPDX-License-Identifier: 0BSD
"""Measure bounded actor work in a disposable copy of the mixed neighborhood."""
import datetime
import argparse
import hashlib
import json
import os
import re
import platform
import uuid
from pathlib import Path
from clone_world import clone_once
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', default='mixed_neighborhood_review')
    parser.add_argument('--compare-contact', action='store_true', help='Compare terrain and a flat box using the same reset actor records')
    args = parser.parse_args()
    source = args.source
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,47}', source):parser.error('Invalid source slot')
    worlds = Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
    slot = 'mixed_actor_' + uuid.uuid4().hex
    copied = clone_once(worlds, source, slot)
    folder = ROOT/'reports/mixed_actor_cost'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    config, _ = parse_args([])
    command = [config.godot, '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60', '--script', 'res://tests/actor_population_cost.gd', '--', '--world-slot='+slot, '--actors', '--ground-cover']
    if args.compare_contact:command.append('--compare-contact')
    metadata = dict(copy=copied, command=command, host=dict(platform=platform.platform(), processor=platform.processor()), **revision_metadata())
    metadata['test_sha256'] = hashlib.sha256((ROOT/'tests/actor_population_cost.gd').read_bytes()).hexdigest()
    metadata['native_sha256'] = {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'addons').glob('*/bin/*.dll')}
    result = execute(command, folder, 100, 'MIXED_ACTOR_COST_COMPLETE')
    unchanged = hashlib.sha256((worlds/(source+'.trw')).read_bytes()).hexdigest() == copied['source_sha256']
    report = ROOT/'reports'/('actor_collision_comparison' if args.compare_contact else 'actor_population_cost')/'result.json'
    if result['required_text_found'] and report.exists():
        (folder/'measurements.json').write_bytes(report.read_bytes())
    metadata.update(result=result, source_unchanged=unchanged)
    (folder/'run.json').write_text(json.dumps(metadata, indent=2))
    print(('PASS ' if result['passed'] and unchanged else 'FAIL ')+str(folder))
    return 0 if result['passed'] and unchanged else 1

if __name__ == '__main__':raise SystemExit(main())
