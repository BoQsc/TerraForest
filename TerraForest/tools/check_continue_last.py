# SPDX-License-Identifier: 0BSD
"""Verify Last World loading presentation and browser fallbacks without opening user saves."""
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
    args = parser.parse_args()
    config, _ = parse_args([])
    folder = ROOT / 'reports/continue_last_presentation' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    engine = ROOT / 'TerraForest.exe' if args.executable else config.godot
    script = ROOT / 'tests/continue_last_presentation.gd'
    record = dict(executable=args.executable, script_sha256=hashlib.sha256(script.read_bytes()).hexdigest(), **revision_metadata())
    if args.executable:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
    command = [str(engine), '--path', str(ROOT / 'dist' if args.executable else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1280x720', '--max-fps', '60', '--log-file', str(folder / 'engine.log'), '--script', str(script), '--', '--continue-last', '--continue-output=' + folder.as_posix()]
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
        result = execute(command, folder, 40, 'CONTINUE_LAST_PRESENTATION checks=', require_resource_budget=True)
    finally:
        subprocess.Popen = original
    record.update(command=command, result=result)
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(('PASS ' if result['passed'] else 'FAIL ') + str(folder))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
