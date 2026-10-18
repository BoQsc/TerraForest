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
    parser.add_argument('--previous-review', action='store_true', help='Open the preserved v1 review save')
    args = parser.parse_args()
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    source, target = ('regional_lake_20261018', 'regional_world_review_v1') if args.previous_review else ('regional_districts_20261018', 'regional_world_review_v2')
    layout = 'lakes' if args.previous_review else 'districts'
    if not (worlds / (target + '.trw')).is_file() and not (worlds / (source + '.trw')).is_file():
        parser.error(f'Prepare the integrated world first: python tools/prepare_combined_world.py --layout {layout} --destination {source}')
    copied = {'pending': not (worlds / (target + '.trw')).exists()}
    if not args.dry_run:
        copied = clone_once(worlds, source, target)
    config, extra = parse_args(['--slot', target, '--generator', '12', '--ground-cover', '--actors', '--vehicle-fleet', '--gameplay-construction', *(['--godot', args.godot] if args.godot else [])])
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
