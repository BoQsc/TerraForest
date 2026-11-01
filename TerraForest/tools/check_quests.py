# SPDX-License-Identifier: 0BSD
"""Exercise bounded quest contracts using debug or release native binaries."""
import argparse
import datetime
import json
import shutil
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    config, _ = parse_args([])
    report = ROOT / 'reports/quests_native' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report.mkdir(parents=True)
    project = ROOT
    if args.release:
        project = ROOT / '.build/quests_release'
        (project / 'addons/player_runtime/bin').mkdir(parents=True, exist_ok=True)
        (project / 'tests').mkdir(exist_ok=True)
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Quest Release Check"\n')
        library = 'player_runtime.windows.template_release.x86_64.dll'
        shutil.copy2(ROOT / 'addons/player_runtime/bin' / library, project / 'addons/player_runtime/bin' / library)
        extension = ROOT / 'addons/player_runtime/player_runtime.gdextension'
        (project / 'addons/player_runtime/player_runtime.gdextension').write_text(extension.read_text().replace('template_debug', 'template_release'))
        shutil.copy2(ROOT / 'tests/quests_native.gd', project / 'tests/quests_native.gd')
    command = [config.godot, '--headless', '--path', str(project), '--script', 'res://tests/quests_native.gd', '--log-file', str(report / 'engine.log')]
    result = execute(command, report, 90, 'QUESTS_NATIVE checks=')
    (report / 'run.json').write_text(json.dumps(dict(release=args.release, result=result, command=command, **revision_metadata()), indent=2) + '\n')
    print(('PASS ' if result['passed'] else 'FAIL ') + str(report))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
