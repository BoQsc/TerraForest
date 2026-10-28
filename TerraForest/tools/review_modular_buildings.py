"""Open the signed walk-around building review without loading player saves."""
import argparse
import datetime
import json
from play_checkpoint import record_and_run
from run import ROOT, parse_args


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--no-tour', action='store_true')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--comparison', action='store_true', help='Use the earlier split-screen comparison instead of walking')
    mode.add_argument('--roof', action='store_true', help='Compare the untouched A0 cottage with the new A2 thin roof')
    mode.add_argument('--shop-roof', action='store_true', help='Compare historical B0 with the approved B2 thin gable roof')
    mode.add_argument('--large-house', action='store_true', help='Inspect the approved additional C1 two-storey house')
    mode.add_argument('--city', action='store_true', help='Inspect six unapproved city building proposals')
    parser.add_argument('--dry-run', action='store_true')
    options = parser.parse_args()
    config, _ = parse_args(['--godot', options.godot] if options.godot else [])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports' / 'playtests' / stamp
    command = [config.godot, '--path', str(ROOT), '--log-file', str(folder / 'engine.log'),
               '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60',
               '--script', 'res://tools/review_modular_buildings.gd', '--', '--temporary',
               *(['--comparison'] if options.comparison else []),
               *(['--roof'] if options.roof else []),
               *(['--shop-roof'] if options.shop_roof else []),
               *(['--large-house'] if options.large_house else []),
               *(['--city'] if options.city else []),
               *(['--guided-tour'] if options.comparison and not options.no_tour else [])]
    details = dict(command=command, temporary=True, label='Building review / Shop B approved addition', utc=stamp,
                   notes='Isolated architecture review, not a gameplay world. A0/B0 are unchanged originals; B1 is approved as an addition. Rejected A1 appears only in the archived comparison. No player saves are read or written.')
    if options.roof:
        details.update(label='A0 original vs A2 thin roof / approved cottage default',
                       notes='Approved A2 roof next to historical A0. New enclosed cottages use this exact A2 design; existing saved buildings are not rewritten. No player saves are read or written by this comparison.')
    if options.shop_roof:
        details.update(label='B0 original vs B2 thin gable roof / approved shop default',
                       notes='Approved B2 roof next to historical B0. New village shops use B2; generated markets also include B1. This comparison does not read or write player saves.')
    if options.large_house:
        details.update(label='House C1 / approved two-storey addition',
                       notes='Isolated viewer of the approved house with balcony, open garage bay and basement. Existing houses and player saves remain unchanged.')
    if options.city:
        details.update(label='City architecture / six proposals pending approval',
                       notes='Warehouse, police, medical centre, research centre, factory and apartments. Review-only native block assets; no generation changes and no player saves read or written.')
    if options.dry_run:
        print(json.dumps(details, indent=2))
        return 0
    return record_and_run(details, folder, details['label'])


if __name__ == '__main__':
    raise SystemExit(main())
