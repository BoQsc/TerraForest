# SPDX-License-Identifier: 0BSD
"""Prepare an existing world's spawn cache without changing its canonical save."""
import argparse
import datetime
import hashlib
import json
import os
import re
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--slot', default='combined_gameplay')
    parser.add_argument('--godot')
    parser.add_argument('--verify', action='store_true', help='Verify fresh-process cache reuse at fullscreen 1080p')
    parser.add_argument('--cache', help='Optional isolated cache, user:// followed by one identifier')
    args = parser.parse_args()
    config, _ = parse_args(['--slot', args.slot, *(['--godot', args.godot] if args.godot else [])])
    if args.cache and not re.fullmatch(r'user://[A-Za-z_][A-Za-z0-9_]{0,79}', args.cache):
        parser.error('Cache must be user:// followed by one identifier')
    source = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds' / (args.slot+'.trw')
    if not source.is_file():
        parser.error('Saved world missing; prepare or save that world first.')
    digest = lambda: hashlib.sha256(source.read_bytes()).hexdigest()
    before = digest()
    folder = ROOT/'reports/world_preparation'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    record = dict(slot=args.slot, source_sha256=before, phases=[], **revision_metadata())
    passed = True
    for phase in (['prepare', 'verify'] if args.verify else ['prepare']):
        output = folder/phase;output.mkdir()
        report = output/'cache.json'
        command = [config.godot, '--path', str(ROOT), '--max-fps', '60',
                   *(['--headless'] if phase=='prepare' else ['--fullscreen', '--resolution', '1920x1080']),
                   '--script', 'res://tools/prepare_world_cache.gd', '--',
                   '--world-slot='+args.slot, '--snapshot-readonly', '--gameplay-construction',
                   '--prepare-report='+str(report), *(['--derived-cache='+args.cache] if args.cache else [])]
        print(phase+': read-only saved-world spawn preparation.', flush=True)
        result = execute(command, output, 110, 'WORLD_CACHE_PREPARATION failures=0')
        metrics = json.loads(report.read_text()) if report.is_file() else {}
        record['phases'].append(dict(command=command, result=result, metrics=metrics))
        passed = passed and result['passed']
        if phase=='verify':
            reused = metrics.get('cache', {}).get('hits', 0)>0
            record['cache_reuse_verified'] = reused
            passed = passed and reused
        if not passed:break
    record['source_unchanged'] = digest()==before
    record['passed'] = passed and record['source_unchanged']
    (folder/'run.json').write_text(json.dumps(record, indent=2))
    print(('PASS ' if record['passed'] else 'FAIL ')+str(folder))
    return 0 if record['passed'] else 1


if __name__=='__main__':raise SystemExit(main())
