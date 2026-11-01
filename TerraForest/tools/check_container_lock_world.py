# SPDX-License-Identifier: 0BSD
"""Inspect generated locks in an owned exploration-test world, then reopen it."""
import argparse
import datetime
import hashlib
import json
import subprocess
from run import ROOT, parse_args
from play_checkpoint import revision_metadata
from run_godot_check import execute, verify_pack_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('exploration_report')
    parser.add_argument('--restore-from')
    parser.add_argument('--pack', action='store_true')
    args = parser.parse_args()
    source = (ROOT / args.exploration_report).resolve()
    if (ROOT / 'reports/exploration_world').resolve() not in source.parents:
        parser.error('Only an owned exploration report is accepted')
    world = json.loads((source / 'created_slot.json').read_text())
    if not world['slot'].startswith('Exploration_'):
        parser.error('Refusing a non-test world')
    config, _ = parse_args([])
    folder = ROOT / 'reports/container_lock_world' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    (folder / 'world.json').write_text(json.dumps(world))
    record = dict(source_generation=str(source), results=[], **revision_metadata())
    if args.pack and not args.restore_from:
        parser.error('Pack mode restores a verified source interaction report')
    if args.restore_from:
        previous = (ROOT / args.restore_from).resolve()
        if (ROOT / 'reports/container_lock_world').resolve() not in previous.parents:
            parser.error('Restore only an owned lock-world report')
        previous_run = json.loads((previous / 'run.json').read_text())
        if not previous_run.get('passed') or json.loads((previous / 'world.json').read_text()) != world:
            parser.error('Source interaction must pass and identify the same owned world')
        (folder / 'expected.bin').write_bytes((previous / 'expected.bin').read_bytes())
        record['restore_from'] = str(previous)
    script = ROOT / 'tests/container_lock_world.gd'
    if args.pack:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        parent = folder / 'window_session_flow.gd'
        parent.write_bytes((ROOT / 'tests/window_session_flow.gd').read_bytes())
        script = folder / 'driver.gd'
        script.write_text((ROOT / 'tests/container_lock_world.gd').read_text().replace('res://tests/window_session_flow.gd', parent.as_posix()), encoding='utf-8')
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for phase in (['restore'] if args.restore_from else ['interact', 'restore']):
            destination = folder / phase
            destination.mkdir()
            command = [config.godot, '--path', str(ROOT / 'dist' if args.pack else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(destination / 'engine.log'), '--script', str(script), '--', '--session-evidence-dir=' + folder.as_posix()]
            if args.pack:command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
            if phase == 'restore':command.append('--restore-locks')
            result = execute(command, destination, 240, 'CONTAINER_LOCK_WORLD checks=', require_resource_budget=True)
            record['results'].append(dict(phase=phase, command=command, result=result))
            record['passed'] = all(row['result']['passed'] for row in record['results'])
            (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
            print(('PASS ' if result['passed'] else 'FAIL ') + phase + ' ' + str(folder), flush=True)
            if not result['passed']:return 1
    finally:
        subprocess.Popen = original
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
