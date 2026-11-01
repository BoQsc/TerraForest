# SPDX-License-Identifier: 0BSD
"""Nonactivating mine review or normal-browser generation and fresh-process restoration."""
import argparse
import datetime
import json
import hashlib
import subprocess
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['review', 'world'])
    parser.add_argument('--resume')
    parser.add_argument('--inside-only', action='store_true', help='Diagnose the saved underground pose after a retained re-entry phase')
    parser.add_argument('--pack', action='store_true', help='Test a matching installed pack after the coordinated export')
    parser.add_argument('--retry', help='Reuse only a CoalMine_* world created by a retained test report')
    parser.add_argument('--complete-return', action='store_true', help='Finish a retained journey whose only remaining walk is the sloping exterior')
    args = parser.parse_args()
    if args.pack and args.mode != 'world':
        parser.error('Pack mode runs the ordinary world journey')
    if args.complete_return and (not args.retry or args.mode != 'world' or args.resume):
        parser.error('Return continuation requires --retry of an owned journey')
    if args.inside_only and (not args.resume or args.mode != 'world'):
        parser.error('Inside-only verification requires --resume')
    base = ROOT / 'reports/coal_mine'
    folder = (ROOT / args.resume).resolve() if args.resume else base / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    if base.resolve() not in folder.parents:
        parser.error('Resume only an owned coal-mine report')
    folder.mkdir(parents=True, exist_ok=True)
    config, _ = parse_args([])
    reuse = ''
    if args.retry:
        previous = (ROOT / args.retry).resolve()
        if base.resolve() not in previous.parents:
            parser.error('Retry only an owned coal-mine report')
        reuse = json.loads((previous / 'created_slot.json').read_text())['slot']
        if not reuse.startswith('CoalMine_') or not reuse.isidentifier():
            parser.error('Not an owned coal-mine test slot')
        (folder / 'created_slot.json').write_text(json.dumps({'slot': reuse, 'reused_from': str(previous)}))
    record = dict(mode=args.mode, pack=args.pack, complete_return=args.complete_return, inside_only=args.inside_only, phases=[], **revision_metadata())
    packed_driver = None
    if args.pack:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        parent = folder / 'window_session_flow.gd'
        parent.write_bytes((ROOT / 'tests/window_session_flow.gd').read_bytes())
        exploration = folder / 'exploration_world.gd'
        exploration.write_text((ROOT / 'tests/exploration_world.gd').read_text().replace('res://tests/window_session_flow.gd', parent.as_posix()))
        packed_driver = folder / 'coal_mine_world.gd'
        packed_driver.write_text((ROOT / 'tests/coal_mine_world.gd').read_text().replace('res://tests/exploration_world.gd', exploration.as_posix()))
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for phase in (['review'] if args.mode == 'review' else ['inside_restore'] if args.inside_only else ['restore', 'inside_restore'] if args.resume else ['create', 'restore', 'inside_restore']):
            destination = folder / (phase + datetime.datetime.now(datetime.timezone.utc).strftime('%H%M%S'))
            destination.mkdir()
            script = 'exploration_review' if args.mode == 'review' else 'coal_mine_world'
            command = [config.godot, '--path', str(ROOT / 'dist' if args.pack else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(destination / 'engine.log'), '--script', str(packed_driver) if args.pack else 'res://tests/' + script + '.gd', '--']
            if args.pack:
                command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
            command += ['--review-output=' + folder.as_posix(), '--coal-only'] if args.mode == 'review' else ['--session-evidence-dir=' + folder.as_posix()]
            if phase in ('restore', 'inside_restore'):
                command.append('--restore-exploration')
                if phase == 'inside_restore':
                    command.append('--coal-inside-restore')
            elif reuse:
                command.append('--coal-reuse-slot=' + reuse)
                if args.complete_return:
                    command.append('--coal-complete-return')
            result = execute(command, destination, 240 if args.mode == 'review' else 800, 'EXPLORATION_REVIEW checks=' if args.mode == 'review' else 'COAL_MINE_WORLD checks=', require_resource_budget=True)
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
