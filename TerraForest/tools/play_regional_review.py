# SPDX-License-Identifier: 0BSD
"""Open a separate editable copy of the integrated regional development world."""
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
    parser.add_argument('--review-version', type=int, choices=[1,2,3,4,5,6,7,8,9,10,11], default=11)
    parser.add_argument('--previous-review', action='store_true', help='Open the preserved v1 review save')
    args = parser.parse_args()
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    version = 1 if args.previous_review else args.review_version
    source = {1:'regional_lake_20261018', 2:'regional_districts_20261018', 3:'regional_access_20261018', 4:'regional_workshops_20261018', 5:'regional_woodland_20261018', 6:'regional_transport_20261018', 7:'planted_neighborhood_42_20261018', 8:'northern_transport_42_20261018', 9:'northern_common_42_20261018', 10:'southern_mixed_42_20261018', 11:'foundation_42_20261020'}[version]
    target = f'regional_world_review_v{version}'
    layout = 'lakes' if version == 1 else 'districts'
    seed_option = ' --seed 42' if version >= 7 else ''
    if not (worlds / (target + '.trw')).is_file() and not (worlds / (source + '.trw')).is_file():
        parser.error(f'Prepare the integrated world first: python tools/prepare_combined_world.py --layout {layout} --destination {source}{seed_option}')
    copied = {'pending': not (worlds / (target + '.trw')).exists()}
    if not args.dry_run:
        copied = clone_once(worlds, source, target)
    config, extra = parse_args(['--slot', target, '--generator', '12' if version == 1 else '13', *(['--seed','42'] if version >= 7 else []), '--ground-cover', '--actors', '--vehicle-fleet', '--gameplay-construction', *(['--godot', args.godot] if args.godot else [])])
    details = launch_details(config, extra)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/playtests' / stamp
    details['command'][1:1] = ['--log-file', str(folder / 'engine.log')]
    details.update(label='Integrated regional world review', source_slot=source, review_copy=copied,
                   notes='Development review; frame spikes remain unresolved. Esc > World lists destinations; development mode enables travel. Review progress is saved separately.')
    if args.dry_run:
        print(json.dumps(details, indent=2)); return 0
    return record_and_run(details, folder, details['label'])

if __name__ == '__main__':
    raise SystemExit(main())
