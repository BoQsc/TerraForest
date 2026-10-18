# SPDX-License-Identifier: 0BSD
"""Check continuous player travel in an existing prepared regional world."""
import argparse
import datetime
import json
import os
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--vehicle', action='store_true', help='Drive the regional arterial instead of walking')
    args = parser.parse_args()
    config, _ = parse_args(['--godot', args.godot] if args.godot else [])
    slot = 'regional_districts_20261018'
    source = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds' / (slot + '.trw')
    if not source.is_file():
        parser.error('Prepare the districts world before running this check.')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/road_travel' / stamp
    test = 'regional_vehicle_travel' if args.vehicle else 'regional_road_travel'
    marker = 'REGIONAL_VEHICLE_TRAVEL failures=0' if args.vehicle else 'REGIONAL_ROAD_TRAVEL failures=0'
    command = [str(config.godot), '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080',
               '--max-fps', '60', '--log-file', str(folder / 'engine.log'),
               '--script', f'res://tests/{test}.gd', '--', '--snapshot-readonly',
               '--world-slot=' + slot, '--ground-cover', '--actors', '--gameplay-construction']
    if args.vehicle: command.append('--vehicle-fleet')
    details = dict(command=command, **revision_metadata(), scope='Arrival check, not a performance qualification')
    if args.dry_run:
        print(json.dumps(details, indent=2)); return 0
    folder.mkdir(parents=True)
    details['result'] = execute(command, folder, 270, marker)
    (folder / 'run.json').write_text(json.dumps(details, indent=2))
    print(('PASS ' if details['result']['passed'] else 'FAIL ') + str(folder))
    return 0 if details['result']['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
