# SPDX-License-Identifier: 0BSD
"""Render inventory navigation without activating or moving the desktop pointer."""
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
    parser.add_argument('--world-report')
    args = parser.parse_args()
    config, _ = parse_args([])
    report = ROOT / 'reports/inventory_navigation' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report.mkdir(parents=True)
    name = 'inventory_navigation_world' if args.world_report else 'inventory_navigation'
    if args.world_report:
        source = (ROOT / args.world_report).resolve()
        if (ROOT / 'reports/player_survival_world').resolve() not in source.parents:
            parser.error('Only owned survival fixtures may be opened')
        receipt = json.loads((source / 'created_slot.json').read_text())
        if not receipt['slot'].startswith('Survival_'):
            parser.error('Not an owned fixture')
        (report / 'world.json').write_text(json.dumps(receipt))
    record = dict(pack=args.pack, world_report=args.world_report, **revision_metadata())
    script = ROOT / 'tests' / (name + '.gd')
    if args.pack:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        text = script.read_text()
        if args.world_report:
            parent = report / 'window_session_flow.gd'
            parent.write_bytes((ROOT / 'tests/window_session_flow.gd').read_bytes())
            text = text.replace('res://tests/window_session_flow.gd', parent.as_posix())
        script = report / 'driver.gd'
        script.write_text(text, encoding='utf-8')
    command = [config.godot, '--path', str(ROOT / 'dist' if args.pack else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(report / 'engine.log'), '--script', str(script), '--', '--evidence=' + report.as_posix(), '--session-evidence-dir=' + report.as_posix()]
    if args.pack:
        command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO();startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        result = execute(command, report, 180 if args.world_report else 90, name.upper() + ' checks=', require_resource_budget=True)
    finally:
        subprocess.Popen = original
    record.update(command=command, result=result, passed=result['passed'])
    (report / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if result['passed'] else 'FAIL ') + str(report))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
