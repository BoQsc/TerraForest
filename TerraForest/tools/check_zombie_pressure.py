# SPDX-License-Identifier: 0BSD
"""Check sustained zombie pressure, moving routes and fair crowd perception without desktop focus."""
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
    parser.add_argument('--executable', action='store_true')
    parser.add_argument('--mine-slot', help='Read-only actual mine journey using an existing owned mine save')
    parser.add_argument('--replay-slot', help='Read-only diagnostic of actual saved residents; use an isolated clone')
    parser.add_argument('--close-resident', type=int, help='Replay next to a specific saved resident')
    parser.add_argument('--route-response', action='store_true', help='Physical narrow-aisle retaliation and elevated corridor regression')
    parser.add_argument('--commitment', action='store_true', help='Sustained engagement, physical recovery and repeated-hit retaliation')
    args = parser.parse_args()
    if sum(bool(value) for value in [args.mine_slot, args.replay_slot, args.route_response, args.commitment]) > 1:
        parser.error('Select only one encounter mode')
    if args.close_resident and not args.replay_slot:
        parser.error('--close-resident requires --replay-slot')
    config, _ = parse_args([])
    folder = ROOT / 'reports/zombie_pressure' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    engine = ROOT / 'TerraForest.exe' if args.executable else config.godot
    test = 'zombie_mine_pursuit' if args.mine_slot else 'zombie_saved_response' if args.replay_slot else 'zombie_route_response' if args.route_response else 'zombie_commitment' if args.commitment else 'zombie_pressure'
    script = ROOT / ('tests/' + test + '.gd')
    record = dict(executable=args.executable, script_sha256=hashlib.sha256(script.read_bytes()).hexdigest(), **revision_metadata())
    if args.executable:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
    command = [str(engine), '--path', str(ROOT / 'dist' if args.executable else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1280x720', '--max-fps', '60', '--log-file', str(folder / 'engine.log'), '--script', str(script), '--', '--pressure-output=' + folder.as_posix()]
    if args.mine_slot:
        command = command[:-1] + ['--fresh-station', '--moving-player', '--mine-slot=' + args.mine_slot, '--mine-output=' + folder.as_posix()]
    if args.replay_slot:
        command = command[:-1] + ['--replay-slot=' + args.replay_slot, '--response-output=' + folder.as_posix()]
        if args.close_resident:
            command.append('--close-resident=' + str(args.close_resident))
    if args.executable:
        command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        marker = 'ZOMBIE_MINE_PURSUIT done' if args.mine_slot else 'ZOMBIE_SAVED_RESPONSE done' if args.replay_slot else 'ZOMBIE_ROUTE_RESPONSE checks=' if args.route_response else 'ZOMBIE_COMMITMENT checks=' if args.commitment else 'ZOMBIE_PRESSURE checks='
        result = execute(command, folder, 200 if args.replay_slot else 180 if args.mine_slot else 60, marker, require_resource_budget=True)
    finally:
        subprocess.Popen = original
    record.update(command=command, result=result, test=test, scope='diagnostic completion, not behavioral acceptance' if args.replay_slot else 'assertion regression')
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(('PASS ' if result['passed'] else 'FAIL ') + str(folder))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
