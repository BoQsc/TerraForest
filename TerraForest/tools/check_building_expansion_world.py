# SPDX-License-Identifier: 0BSD
"""Matched expansion comparisons or a saved review clone plus fresh-process restore."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import uuid
from clone_world import clone_once
from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--house', action='store_true')
    parser.add_argument('--persist', action='store_true')
    parser.add_argument('--routes', action='store_true')
    parser.add_argument('--travel', action='store_true', help='Matched actual-player traversal through the surveyed civic streets')
    parser.add_argument('--only', choices=['trader_t1','town_hall_t1','church_c1','school_s2','warehouse_w1','cottage_a2','shop_b2','shop_b1','house_c1'], help='Scope a follow-up to one named revision')
    parser.add_argument('--after-only', action='store_true', help='Repeat only the changed candidate against an already retained R1 baseline')
    options = parser.parse_args()
    engine = parse_args(['--godot', options.godot] if options.godot else [])[0].godot
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT/'reports/building_expansion'/('persistent_' if options.persist else 'paired_')/stamp
    folder.mkdir(parents=True)
    record = {**revision_metadata(), 'phases': [], 'house': options.house}
    source_manifest = ROOT/('reports/building_expansion/house_slot.json' if options.house else 'reports/civic_world/slot.json')
    source = json.loads(source_manifest.read_text())['slot']
    worlds = Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
    original_hash = hashlib.sha256((worlds/(source+'.trw')).read_bytes()).hexdigest()
    shared = ['--expansion-house-only'] if options.house else []
    if options.only: shared += ['--expansion-only='+options.only]
    if options.travel: shared += ['--expansion-travel', '--expansion-quick']
    if options.persist:
        slot = 'Expansion_E2_'+('house_' if options.house else 'civic_')+uuid.uuid4().hex[:8]
        record['clone'] = clone_once(worlds, source, slot)
        shared += ['--expansion-slot='+slot, '--expansion-quick']
        phases = [('save', ['--expansion-after', '--expansion-save']), ('reopen', ['--expansion-reopen'])]
    else:
        phases = [('R1', []), ('E2', ['--expansion-after']+(['--expansion-routes'] if options.routes else []))]
        if options.after_only: phases = phases[1:]
    for name, arguments in phases:
        output = folder/name
        output.mkdir()
        command = [engine, '--path', str(ROOT), '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60',
                   '--log-file', str(output/'engine.log'), '--script', 'res://tests/building_expansion_world.gd', '--', *shared, *arguments]
        result = execute(command, output, 1200 if options.routes else 600, 'BUILDING_EXPANSION_WORLD checks=')
        record['phases'].append({'phase': name, 'command': command, **result})
        record['source_unchanged'] = hashlib.sha256((worlds/(source+'.trw')).read_bytes()).hexdigest() == original_hash
        (folder/'run.json').write_text(json.dumps(record, indent=2)+'\n')
        print(('PASS ' if result['passed'] else 'FAIL ')+name+' '+str(output), flush=True)
        if not result['passed'] or not record['source_unchanged']: return 1
    if options.persist:
        manifest = ROOT/'reports/building_expansion'/('review_house_slot.json' if options.house else 'review_slot.json')
        manifest.write_text(json.dumps({'slot': slot, 'source': source, 'evidence': str(folder), 'revision': 'E2',
            'candidate_manifest_sha256': hashlib.sha256((ROOT/'reviews/building_expansion/provenance.json').read_bytes()).hexdigest(),
            'world_sha256': hashlib.sha256((worlds/(slot+'.trw')).read_bytes()).hexdigest(),
            'native_sha256': hashlib.sha256((ROOT/'addons/structures/bin/structures.windows.template_debug.x86_64.dll').read_bytes()).hexdigest()}, indent=2)+'\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
