# SPDX-License-Identifier: 0BSD
"""Check quest ownership publication and compound-save restoration in real generation."""
import argparse
import datetime
import hashlib
import json
import subprocess
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true')
    parser.add_argument('--originals', action='store_true')
    reuse = parser.add_mutually_exclusive_group()
    reuse.add_argument('--restore-report')
    reuse.add_argument('--exercise-report')
    reuse.add_argument('--baseline-report')
    args = parser.parse_args()
    config, _ = parse_args([])
    base = ROOT / 'reports/quests_world'
    folder = base / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    source_report = args.restore_report or args.exercise_report or args.baseline_report
    if source_report:
        source = (ROOT / source_report).resolve()
        if base.resolve() not in source.parents:
            parser.error('Restore only owned quest reports')
        receipt = json.loads((source / 'created_slot.json').read_text())
        if not receipt['slot'].startswith('Quests_'):
            parser.error('Not an owned quest fixture')
        for name in (['created_slot.json'] if args.baseline_report else ['expected.bin', 'created_slot.json']):
            (folder / name).write_bytes((source / name).read_bytes())
    record = dict(pack=args.pack, originals=args.originals, restore_report=args.restore_report, exercise_report=args.exercise_report, baseline_report=args.baseline_report, phases=[], **revision_metadata())
    script = ROOT / 'tests/quests_world.gd'
    if args.pack:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        parent = folder / 'window_session_flow.gd'
        parent.write_bytes((ROOT / 'tests/window_session_flow.gd').read_bytes())
        script = folder / 'driver.gd'
        script.write_text((ROOT / 'tests/quests_world.gd').read_text().replace('res://tests/window_session_flow.gd', parent.as_posix()), encoding='utf-8')
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for phase in (['create_originals', 'baseline_reopen'] if args.originals and not source_report else ['baseline', 'baseline_reopen'] if args.baseline_report else ['restore'] if args.restore_report else ['exercise', 'restore'] if args.exercise_report else ['create', 'restore']):
            destination = folder / phase
            destination.mkdir()
            command = [config.godot, '--path', str(ROOT / 'dist' if args.pack else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(destination / 'engine.log'), '--script', str(script), '--', '--session-evidence-dir=' + folder.as_posix()]
            if args.pack:
                command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
            if args.originals:
                command.append('--verify-originals')
            if phase == 'restore':
                command.append('--restore-quests')
            elif phase == 'exercise':
                command.append('--exercise-quests')
            elif phase.startswith('baseline'):
                command.append('--baseline-check')
                if phase == 'baseline_reopen':
                    command.append('--baseline-reopen')
            result = execute(command, destination, 800, 'QUESTS_WORLD checks=', require_resource_budget=True)
            record['phases'].append(dict(phase=phase, command=command, result=result))
            record['passed'] = all(row['result']['passed'] for row in record['phases'])
            (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
            print(('PASS ' if result['passed'] else 'FAIL ') + phase + ' ' + str(folder), flush=True)
            if not result['passed']:
                return 1
    finally:
        subprocess.Popen = original
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
