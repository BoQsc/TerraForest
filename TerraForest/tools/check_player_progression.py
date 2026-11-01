# SPDX-License-Identifier: 0BSD
"""Check native progression or ordinary generated-world earning and restoration."""
import argparse
import datetime
import hashlib
import json
import shutil
import subprocess

from run import ROOT, parse_args
from play_checkpoint import revision_metadata
from run_godot_check import execute, verify_pack_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--world-report')
    parser.add_argument('--pack-restore')
    args = parser.parse_args()
    config, _ = parse_args([])
    report = ROOT / 'reports/player_progression' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report.mkdir(parents=True)
    record = dict(results=[], **revision_metadata())
    project = ROOT
    script = ROOT / 'tests/player_progression.gd'
    phases = ['native']
    marker = 'PLAYER_PROGRESSION '
    if args.world_report:
        source = (ROOT / args.world_report).resolve()
        if (ROOT / 'reports/exploration_world').resolve() not in source.parents:
            parser.error('Only owned exploration-test reports are allowed')
        world = json.loads((source / 'created_slot.json').read_text())
        if not world['slot'].startswith('Exploration_'):
            parser.error('Refusing non-test world')
        (report / 'world.json').write_text(json.dumps(world))
        script = ROOT / 'tests/player_progression_world.gd'
        phases = ['earn', 'restore']
        marker = 'PLAYER_PROGRESSION_WORLD checks='
        record['source_generation'] = str(source)
    if args.pack_restore:
        if not args.world_report or args.release:
            parser.error('Pack restoration requires world report, not release fixture')
        previous = (ROOT / args.pack_restore).resolve()
        if (ROOT / 'reports/player_progression').resolve() not in previous.parents:
            parser.error('Only owned progression evidence is allowed')
        if not json.loads((previous / 'run.json').read_text()).get('passed') or json.loads((previous / 'world.json').read_text()) != world:
            parser.error('Source evidence must pass and refer to this world')
        shutil.copy2(previous / 'expected.bin', report / 'expected.bin')
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        project = ROOT / 'dist'
        parent = report / 'window_session_flow.gd'
        shutil.copy2(ROOT / 'tests/window_session_flow.gd', parent)
        driver = report / 'driver.gd'
        driver.write_text(script.read_text().replace('res://tests/window_session_flow.gd', parent.as_posix()), encoding='utf-8')
        script = driver
        phases = ['restore']
    if args.release:
        if args.world_report:parser.error('Release fixture is native-only; use matching pack for world checks')
        project = ROOT / '.build/progression_release'
        (project / 'addons/player_runtime/bin').mkdir(parents=True, exist_ok=True)
        (project / 'tests').mkdir(exist_ok=True)
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Progression Release Check"\n')
        library = 'player_runtime.windows.template_release.x86_64.dll'
        shutil.copy2(ROOT / 'addons/player_runtime/bin' / library, project / 'addons/player_runtime/bin' / library)
        extension = ROOT / 'addons/player_runtime/player_runtime.gdextension'
        (project / 'addons/player_runtime/player_runtime.gdextension').write_text(extension.read_text().replace('template_debug', 'template_release'))
        shutil.copy2(script, project / 'tests/player_progression.gd')
        script = project / 'tests/player_progression.gd'
    record['release_fixture'] = args.release
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for phase in phases:
            destination = report / phase
            destination.mkdir()
            command = [config.godot, '--path', str(project), '--log-file', str(destination / 'engine.log'), '--script', str(script)]
            if args.pack_restore:command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
            if args.world_report:
                command += ['--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--', '--session-evidence-dir=' + report.as_posix()]
                if phase == 'restore':command.append('--restore-progression')
            else:command.append('--headless')
            result = execute(command, destination, 300 if args.world_report else 40, marker, require_resource_budget=bool(args.world_report))
            record['results'].append(dict(phase=phase, command=command, result=result))
            record['passed'] = all(row['result']['passed'] for row in record['results'])
            (report / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
            print(('PASS ' if result['passed'] else 'FAIL ') + phase + ' ' + str(report), flush=True)
            if not result['passed']:return 1
    finally:
        subprocess.Popen = original
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
