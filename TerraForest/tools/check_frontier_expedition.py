# SPDX-License-Identifier: 0BSD
"""Exercise ordinary expedition creation and fresh-process physical travel."""
import argparse
import datetime
import hashlib
import json
import subprocess
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reuse-report')
    parser.add_argument('--stage', choices=['create', 'notices_reload', 'intro_reload', 'boarding', 'driver', 'depart', 'resume', 'clear', 'clear_resume', 'mine_resume', 'claim_resume', 'home_resume', 'reward_reload'], default='create')
    parser.add_argument('--notices-only', action='store_true')
    parser.add_argument('--pack', action='store_true')
    parser.add_argument('--installed-executable', action='store_true')
    args = parser.parse_args()
    if args.installed_executable and not args.pack:
        parser.error('The installed executable must use the installed pack')
    if (args.stage != 'create') != bool(args.reuse_report):
        parser.error('Existing stages require an owned report; create uses a new world')
    config, _ = parse_args([])
    base = ROOT / 'reports/frontier_expedition'
    folder = base / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    if args.reuse_report:
        source = (ROOT / args.reuse_report).resolve()
        if base.resolve() not in source.parents:
            parser.error('Reuse only owned expedition evidence')
        receipt = json.loads((source / 'world.json').read_text())
        if not receipt['slot'].startswith('Expedition_1703_'):
            parser.error('Not an owned expedition fixture')
        for name in ['world.json', 'expected.bin', 'completed.bin']:
            if (source / name).is_file():
                (folder / name).write_bytes((source / name).read_bytes())
    script = ROOT / 'tests/frontier_expedition_world.gd'
    native = verify_pack_native() if args.pack else {}
    if args.pack:
        parent = folder / 'window_session_flow.gd'
        parent.write_bytes((ROOT / 'tests/window_session_flow.gd').read_bytes())
        ride = folder / 'trader_ride_world.gd'
        ride.write_text((ROOT / 'tests/trader_ride_world.gd').read_text().replace('res://tests/window_session_flow.gd', parent.as_posix()), encoding='utf-8')
        script = folder / 'driver.gd'
        script.write_text((ROOT / 'tests/frontier_expedition_world.gd').read_text().replace('res://tests/trader_ride_world.gd', ride.as_posix()), encoding='utf-8')
    command = [config.godot, '--path', str(ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(folder / 'engine.log'), '--script', str(script), '--', '--session-evidence-dir=' + folder.as_posix(), '--ride-stage=' + args.stage, '--wakeup-test']
    if args.notices_only:
        command.append('--notices-only')
    if args.installed_executable:
        command[0] = str(ROOT / 'TerraForest.exe')
    if args.pack:
        command[command.index('--path') + 1] = str(ROOT / 'dist')
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
        result = execute(command, folder, 1400, 'FRONTIER_EXPEDITION_WORLD checks=', require_resource_budget=True)
    finally:
        subprocess.Popen = original
    record = dict(stage=args.stage, pack=args.pack, native_sha256=native, reused=args.reuse_report, command=command, result=result, test_sha256=hashlib.sha256(script.read_bytes()).hexdigest(), **revision_metadata())
    record['executable_sha256'] = hashlib.sha256(Path(command[0]).read_bytes()).hexdigest()
    if args.pack:
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(('PASS ' if result['passed'] else 'FAIL ') + str(folder), flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
