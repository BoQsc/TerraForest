# SPDX-License-Identifier: 0BSD
"""Normal-browser cave generation, player access, loot and fresh-process restore."""
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
    parser.add_argument('--pack', action='store_true')
    parser.add_argument('--resume')
    args = parser.parse_args()
    config, _ = parse_args([])
    base = ROOT / 'reports/exploration_world'
    folder = (ROOT / args.resume).resolve() if args.resume else base / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    if base.resolve() not in folder.parents:
        parser.error('Resume only an owned exploration report')
    folder.mkdir(parents=True, exist_ok=True)
    record = dict(pack=args.pack, phases=[], **revision_metadata())
    script = ROOT / 'tests/exploration_world.gd'
    if args.pack:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        parent = folder / 'window_session_flow.gd'
        parent.write_bytes((ROOT / 'tests/window_session_flow.gd').read_bytes())
        script = folder / 'driver.gd'
        script.write_text((ROOT / 'tests/exploration_world.gd').read_text().replace('res://tests/window_session_flow.gd', parent.as_posix()), encoding='utf-8')
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for phase in (['restore'] if args.resume else ['create', 'restore']):
            destination = folder / (phase + datetime.datetime.now(datetime.timezone.utc).strftime('%H%M%S'))
            destination.mkdir()
            command = [config.godot, '--path', str(ROOT / 'dist' if args.pack else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(destination / 'engine.log'), '--script', str(script), '--', '--session-evidence-dir=' + folder.as_posix()]
            if args.pack:
                command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
            if phase == 'restore':
                command.append('--restore-exploration')
            result = execute(command, destination, 700, 'EXPLORATION_WORLD checks=', require_resource_budget=True)
            record['phases'].append(dict(phase=phase, command=command, result=result))
            record['passed'] = all(row['result']['passed'] for row in record['phases'])
            (folder / ('resume.json' if args.resume else 'run.json')).write_text(json.dumps(record, indent=2) + '\n')
            print(('PASS ' if result['passed'] else 'FAIL ') + phase + ' ' + str(folder), flush=True)
            if not result['passed']:
                return 1
    finally:
        subprocess.Popen = original
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
