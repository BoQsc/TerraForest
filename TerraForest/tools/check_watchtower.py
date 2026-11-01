# SPDX-License-Identifier: 0BSD
"""Check the native modular lookout and its physical stair routes, without focus."""
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
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--bake', action='store_true')
    parser.add_argument('--pack', action='store_true')
    args = parser.parse_args()
    if args.pack and args.bake:
        parser.error('Bake from source, not a read-only game pack')
    config, _ = parse_args([])
    folder = ROOT / 'reports/watchtower' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    record = dict(pack=args.pack, scope='Isolated lookout geometry, binary persistence and physical stair traversal; not ordinary generation or terrain-fit acceptance.', **revision_metadata())
    script = 'res://tests/watchtower_review.gd'
    if args.pack:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        driver = folder / 'driver.gd'
        driver.write_bytes((ROOT / 'tests/watchtower_review.gd').read_bytes())
        script = str(driver)
        record['driver_scope'] = 'External assertion driver; recipe and exact baked W1 resource load from the installed pack.'
    command = [config.godot, '--path', str(ROOT / 'dist' if args.pack else ROOT), '--max-fps', '60', '--log-file', str(folder / 'engine.log'), '--script', script]
    if args.pack:
        command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
    if args.render:
        command.extend(['--windowed', '--position', '-2400,-1600', '--resolution', '1600x900'])
    else:
        command.append('--headless')
    command.append('--')
    if args.render:
        command.append('--review-output=' + folder.as_posix())
    if args.bake:
        command.append('--bake-watchtower')
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        result = execute(command, folder, 300, 'WATCHTOWER_REVIEW checks=', require_resource_budget=args.render)
    finally:
        subprocess.Popen = original
    (folder / 'run.json').write_text(json.dumps(dict(command=command, result=result, **record), indent=2) + '\n')
    print(('PASS ' if result['passed'] else 'FAIL ') + str(folder), flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
