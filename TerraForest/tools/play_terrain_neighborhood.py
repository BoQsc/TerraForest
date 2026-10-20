# SPDX-License-Identifier: 0BSD
"""Open the saved terrain-fitting neighborhood, preserving its prepared source."""
import argparse
import datetime
import json
import os
from pathlib import Path
from clone_world import clone_once
from play_checkpoint import record_and_run
from run import ROOT, parse_args, launch_details

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--godot')
    parser.add_argument('--previous-review', action='store_true')
    parser.add_argument('--review-version', type=int, choices=[1,2,3,4], default=4)
    options = parser.parse_args()
    version = 1 if options.previous_review else options.review_version
    source = {1:'terrain_fitted_neighborhood_20261020',2:'terrain_ranked_neighborhood_20261020',3:'terrain_connected_clear_20261020',4:'two_settlements_paved_20261020'}[version]
    target = 'terrain_fitted_neighborhood_review' if version == 1 else f'terrain_fitted_neighborhood_review_v{version}'
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    if not (worlds / (source + '.trw')).is_file() and not (worlds / (target + '.trw')).is_file():
        parser.error('The prepared neighborhood is missing. This launcher requires its baked save.')
    if not options.dry_run:
        clone_once(worlds, source, target)
    config, extra = parse_args(['--slot', target, '--generator', '17', '--seed', '42',
        '--ground-cover', *(['--godot', options.godot] if options.godot else [])])
    details = launch_details(config, extra)
    details.update(label='Terrain-fitting neighborhood review', source_slot=source,
        notes='Version4: twenty buildings across a northern neighborhood and central market, joined by a forest road. Earlier versions remain available. Remaining regional locations, lakes, landscape quality and sustained performance are unfinished.')
    if options.dry_run:
        print(json.dumps(details, indent=2)); return 0
    folder = ROOT / 'reports/playtests' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    details['command'][1:1] = ['--log-file', str(folder / 'engine.log')]
    return record_and_run(details, folder, details['label'])
if __name__ == '__main__':
    raise SystemExit(main())
