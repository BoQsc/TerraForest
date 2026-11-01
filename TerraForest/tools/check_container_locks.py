# SPDX-License-Identifier: 0BSD
"""Validate native container locks and legacy storage using debug or release DLLs."""
import argparse
import datetime
import hashlib
import json
import shutil

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import execute


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report = ROOT / 'reports/container_locks' / stamp
    report.mkdir(parents=True)
    names = ['container_locks', 'container_store', 'container_drag', 'container_capacity', 'inventory_transfer']
    project = ROOT
    record = dict(release=args.release, results=[], **revision_metadata())
    target = 'template_release' if args.release else 'template_debug'
    library = f'player_runtime.windows.{target}.x86_64.dll'
    original = ROOT / 'addons/player_runtime/bin' / library
    record['native_sha256'] = hashlib.sha256(original.read_bytes()).hexdigest()
    if args.release:
        project = ROOT / '.build/container_locks_release'
        (project / 'addons/player_runtime/bin').mkdir(parents=True, exist_ok=True)
        (project / 'tests').mkdir(exist_ok=True)
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Container Lock Release Check"\n')
        shutil.copy2(original, project / 'addons/player_runtime/bin' / library)
        extension = ROOT / 'addons/player_runtime/player_runtime.gdextension'
        (project / 'addons/player_runtime/player_runtime.gdextension').write_text(extension.read_text().replace('template_debug', 'template_release'))
        for name in names:
            shutil.copy2(ROOT / 'tests' / (name + '.gd'), project / 'tests' / (name + '.gd'))
    for name in names:
        destination = report / name
        destination.mkdir()
        command = [config.godot, '--headless', '--path', str(project), '--log-file', str(destination / 'engine.log'), '--script', f'res://tests/{name}.gd']
        result = execute(command, destination, 30, name.upper())
        record['results'].append(dict(test=name, command=command, result=result))
        print(('PASS ' if result['passed'] else 'FAIL ') + name, flush=True)
    record['passed'] = all(row['result']['passed'] for row in record['results'])
    (report / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(report), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
