# SPDX-License-Identifier: 0BSD
"""Open a verified expansion review clone, preserving the approved baseline world."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from run import ROOT, parse_args


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--house', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    engine = parse_args(['--godot', args.godot] if args.godot else [])[0].godot
    manifest = ROOT/'reports/building_expansion'/('review_house_slot.json' if args.house else 'review_slot.json')
    saved = json.loads(manifest.read_text())
    slot = saved['slot']
    if not re.fullmatch(r'Expansion_E2_(house|civic)_[0-9a-f]{8}', slot): raise ValueError('Not an isolated expansion review clone')
    evidence = json.loads((Path(saved['evidence'])/'run.json').read_text())
    if saved.get('revision') != 'E2' or not evidence.get('source_unchanged') or not all(row['passed'] for row in evidence['phases']) or len(evidence['phases']) != 2:
        raise ValueError('Save and fresh-process restoration must both pass before review')
    for field, path in [('candidate_manifest_sha256', ROOT/'reviews/building_expansion/provenance.json'),
                        ('world_sha256', Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'/(slot+'.trw')),
                        ('native_sha256', ROOT/'addons/structures/bin/structures.windows.template_debug.x86_64.dll')]:
        if saved.get(field) != hashlib.sha256(path.read_bytes()).hexdigest(): raise ValueError('Review checkpoint is stale: '+field)
    command = [sys.executable, str(ROOT/'tools/run.py'), '--godot', engine, '--slot', slot, '--ground-cover', '--actors', '--vehicle-fleet', '--gameplay-construction', '--no-zombies', '--building-expansion-review', '--snapshot-readonly']
    if args.dry_run: print(json.dumps({'slot': slot, 'command': command}, indent=2)); return 0
    print('Opening verified E2 review; test edits are discarded on closing.', flush=True)
    return subprocess.call(command)


if __name__ == '__main__':
    raise SystemExit(main())
