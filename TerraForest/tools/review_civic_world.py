# SPDX-License-Identifier: 0BSD
"""Open the isolated, fully generated civic approval world. Existing saves stay intact."""
import argparse
import json
import subprocess
import sys
from pathlib import Path
from run import ROOT, parse_args


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--create', action='store_true', help='Generate another uniquely named review world first')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    runtime, _ = parse_args(['--godot', args.godot] if args.godot else [])
    manifest = ROOT / 'reports/civic_world/slot.json'
    if args.create or not manifest.is_file():
        if args.dry_run:
            print('A new isolated CivicReview_1703_* world would be generated.'); return 0
        command = [sys.executable, str(ROOT / 'tools/run_godot_check.py'), 'civic_world',
                   '--godot', runtime.godot, '--timeout', '600', '--require', 'CIVIC_WORLD checks=', '--', '--build-civic']
        if subprocess.call(command): return 1
    slot = json.loads(manifest.read_text(encoding='utf-8'))['slot']
    import re
    if not re.fullmatch(r'CivicReview_1703_[0-9a-f]{8}', slot):
        raise ValueError('Review manifest does not identify an isolated civic world')
    command = [sys.executable, str(ROOT / 'tools/run.py'), '--godot', runtime.godot,
               '--slot', slot, '--ground-cover', '--actors', '--vehicle-fleet',
               '--gameplay-construction', '--no-zombies']
    if args.dry_run:
        print(json.dumps({'slot': slot, 'command': command}, indent=2)); return 0
    return subprocess.call(command)


if __name__ == '__main__':
    raise SystemExit(main())
