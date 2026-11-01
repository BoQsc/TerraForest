# SPDX-License-Identifier: 0BSD
"""Run isolated survival contracts, UI adapters or offline asset baking."""
import argparse
import datetime
import json
import shutil
import subprocess
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['native', 'ui', 'assets'])
    parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    if args.release and args.mode != 'native':parser.error('Release fixture is native only')
    config, _ = parse_args([])
    report = ROOT / 'reports/player_survival' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report.mkdir(parents=True)
    record = dict(mode=args.mode, release=args.release, results=[], **revision_metadata())
    project = ROOT
    if args.release:
        project = ROOT / '.build/survival_release'
        (project / 'addons/player_runtime/bin').mkdir(parents=True, exist_ok=True)
        (project / 'tests').mkdir(exist_ok=True)
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Survival Release Check"\n')
        library = 'player_runtime.windows.template_release.x86_64.dll'
        shutil.copy2(ROOT / 'addons/player_runtime/bin' / library, project / 'addons/player_runtime/bin' / library)
        extension = ROOT / 'addons/player_runtime/player_runtime.gdextension'
        (project / 'addons/player_runtime/player_runtime.gdextension').write_text(extension.read_text().replace('template_debug', 'template_release'))
        shutil.copy2(ROOT / 'tests/player_survival.gd', project / 'tests/player_survival.gd')
    jobs = [('native', 'res://tests/player_survival.gd', True, 'PLAYER_SURVIVAL ')] if args.mode == 'native' else [('ui', 'res://tests/player_survival_ui.gd', True, 'PLAYER_SURVIVAL_UI ')]
    if args.mode == 'assets':jobs = [('models', 'res://tools/bake_consumables.gd', True, 'CONSUMABLE_BAKE complete'), ('icons', 'res://tests/bake_item_icons.gd', False, 'ICON_BAKE failures=0')]
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO();startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for label, script, headless, marker in jobs:
            destination = report / label;destination.mkdir()
            command = [config.godot, '--path', str(project), '--log-file', str(destination / 'engine.log'), '--script', script]
            command += ['--headless'] if headless else ['--windowed', '--position', '-2400,-1600', '--resolution', '512x512', '--max-fps', '60']
            if label == 'icons':command += ['--', '--icons-only']
            result = execute(command, destination, 90, marker)
            record['results'].append(dict(label=label, result=result, command=command))
            record['passed'] = all(row['result']['passed'] for row in record['results'])
            (report / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
            print(('PASS ' if result['passed'] else 'FAIL ') + label + ' ' + str(report), flush=True)
            if not result['passed']:return 1
    finally:subprocess.Popen = original
    return 0


if __name__ == '__main__':raise SystemExit(main())
