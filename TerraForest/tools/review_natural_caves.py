# SPDX-License-Identifier: 0BSD
"""Open a disposable, on-foot natural cave review using the normal world scene."""
import argparse
import datetime
from run import ROOT, parse_args, launch_details
from play_checkpoint import record_and_run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--smoke', action='store_true')
    options = parser.parse_args()
    config, _ = parse_args(['--generator', '6', '--seed', '1703', '--slot', 'natural_cave_review', '--temporary',
                           *(['--godot', options.godot] if options.godot else [])])
    details = launch_details(config, ['--gameplay-construction', *(['--review-smoke'] if options.smoke else [])])
    index = details['command'].index('res://demo/world.tscn')
    details['command'][index:index+1] = ['--script', 'res://tools/review_natural_caves.gd']
    if options.dry_run:
        import json
        print(json.dumps(details, indent=2))
        return 0
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    return record_and_run(details, ROOT / 'reports/playtests' / stamp, 'Natural cave review')


if __name__ == '__main__':raise SystemExit(main())
