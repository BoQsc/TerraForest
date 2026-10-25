"""Open the isolated, side-by-side building proposals without loading player saves."""
import argparse
import datetime
import json
from play_checkpoint import record_and_run
from run import ROOT, parse_args


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--no-tour', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    options = parser.parse_args()
    config, _ = parse_args(['--godot', options.godot] if options.godot else [])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports' / 'playtests' / stamp
    command = [config.godot, '--path', str(ROOT), '--log-file', str(folder / 'engine.log'),
               '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60',
               '--script', 'res://tools/review_modular_buildings.gd', '--', '--temporary',
               *([] if options.no_tour else ['--guided-tour'])]
    details = dict(command=command, temporary=True, label='Building proposals R1', utc=stamp,
                   notes='Isolated architecture comparison, not a gameplay world. Originals are unchanged; candidates are unapproved. No player saves are read or written.')
    if options.dry_run:
        print(json.dumps(details, indent=2))
        return 0
    return record_and_run(details, folder, details['label'])


if __name__ == '__main__':
    raise SystemExit(main())
