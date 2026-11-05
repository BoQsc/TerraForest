# SPDX-License-Identifier: 0BSD
"""Validate UI-set discovery, activation and rendered previews without desktop focus."""
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
    parser.add_argument('--flow', action='store_true', help='Exercise real open/save/reopen/return and photographs with Survey active')
    parser.add_argument('--loading', action='store_true', help='Check live measured loading, diagnostics and layout with Survey active')
    parser.add_argument('--photographs', action='store_true', help='Check automatic arrival capture and rendered browser/loading photographs in every set')
    args = parser.parse_args()
    if sum([args.flow, args.loading, args.photographs]) > 1:
        parser.error('Select one check')
    config, _ = parse_args([])
    folder = ROOT / 'reports/ui_sets' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    script = ROOT / ('tests/ui_set_session_flow.gd' if args.flow else 'tests/loading_progress_ui.gd' if args.loading else 'tests/world_photo_display.gd' if args.photographs else 'tests/ui_sets.gd')
    if args.pack and args.flow:
        parent = folder / 'window_session_flow.gd'
        parent.write_bytes((ROOT / 'tests/window_session_flow.gd').read_bytes())
        driver = folder / 'driver.gd'
        driver.write_text(script.read_text().replace('res://tests/window_session_flow.gd', parent.as_posix()), encoding='utf-8')
        script = driver
    record = dict(pack=args.pack, script_sha256=hashlib.sha256(script.read_bytes()).hexdigest(), **revision_metadata())
    command = [str(ROOT / 'TerraForest.exe' if args.pack else config.godot), '--path', str(ROOT / 'dist' if args.pack else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(folder / 'engine.log'), '--script', str(script), '--', '--ui-output=' + folder.as_posix()]
    if args.flow:
        command += ['--ui-set=survey', '--session-evidence-dir=' + folder.as_posix()]
    if args.loading:
        command += ['--ui-set=survey']
    if args.pack:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
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
        marker = 'WINDOW_SESSION_FLOW checks=' if args.flow else 'LOADING_PROGRESS_UI failures=' if args.loading else 'WORLD_PHOTO_DISPLAY checks=' if args.photographs else 'UI_SETS checks='
        result = execute(command, folder, 260 if args.flow else 120 if args.loading else 100, marker, require_resource_budget=True)
    finally:
        subprocess.Popen = original
    record.update(command=command, result=result, flow=args.flow, loading=args.loading, photographs=args.photographs)
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(('PASS ' if result['passed'] else 'FAIL ') + str(folder))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
