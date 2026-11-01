# SPDX-License-Identifier: 0BSD
"""Normal-browser sleeper generation and fresh-process verification, without pointer capture."""
import argparse
import datetime
import hashlib
import json
import subprocess

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true')
    parser.add_argument('--resume', type=str)
    parser.add_argument('--admission-only', action='store_true')
    args = parser.parse_args()
    if args.admission_only and not args.resume:
        parser.error('Admission check requires an owned existing report')
    config, _ = parse_args([])
    folder = (ROOT / args.resume).resolve() if args.resume else ROOT / 'reports/house_sleepers' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    if args.resume and (ROOT / 'reports/house_sleepers').resolve() not in folder.parents:
        parser.error('Resume only a report under reports/house_sleepers')
    folder.mkdir(parents=True, exist_ok=True)
    record = dict(pack=args.pack, phases=[], **revision_metadata())
    script = ROOT / 'tests/house_sleepers_world.gd'
    if args.pack:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        parent = folder / 'window_session_flow.gd'
        parent.write_bytes((ROOT / 'tests/window_session_flow.gd').read_bytes())
        script = folder / 'driver.gd'
        script.write_text((ROOT / 'tests/house_sleepers_world.gd').read_text().replace('res://tests/window_session_flow.gd', parent.as_posix()), encoding='utf-8')
    record['driver_sha256'] = hashlib.sha256(script.read_bytes()).hexdigest()
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for phase in (['admission'] if args.admission_only else ['restore', 'cleared'] if args.resume else ['create', 'restore', 'cleared', 'admission']):
            destination = folder / (phase + '_resume_' + datetime.datetime.now(datetime.timezone.utc).strftime('%H%M%S') if args.resume else phase)
            destination.mkdir()
            command = [config.godot, '--path', str(ROOT / 'dist' if args.pack else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(destination / 'engine.log'), '--script', str(script), '--', '--session-evidence-dir=' + folder.as_posix()]
            if args.pack:
                command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
            if phase == 'restore':
                command.append('--restore-homes')
            if phase == 'cleared':
                command.append('--cleared-homes')
            if phase == 'admission':
                command.append('--admission-homes')
            result = execute(command, destination, 650, 'HOUSE_SLEEPERS_WORLD checks=', require_resource_budget=True)
            record['phases'].append(dict(phase=phase, command=command, result=result))
            record['passed'] = len(record['phases']) == (1 if args.admission_only else 2 if args.resume else 4) and all(row['result']['passed'] for row in record['phases'])
            (folder / ('admission.json' if args.admission_only else 'resume.json' if args.resume else 'run.json')).write_text(json.dumps(record, indent=2) + '\n')
            print(('PASS ' if result['passed'] else 'FAIL ') + phase + ' ' + str(folder), flush=True)
            if not result['passed']:
                return 1
    finally:
        subprocess.Popen = original
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
