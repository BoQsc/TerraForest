# SPDX-License-Identifier: 0BSD
"""Verify new corpse clothing and minimal starters using isolated native/world fixtures."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid
from clone_world import clone_once
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world', action='store_true')
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--pack', action='store_true')
    parser.add_argument('--source-report', help='Owned survival report to clone for world checks')
    args = parser.parse_args()
    if args.release and args.world:parser.error('Release checks are native only')
    if args.pack and not args.world:parser.error('Package checks require --world')
    config, _ = parse_args([])
    folder = ROOT / 'reports/clothing_loot' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    record = dict(world=args.world, release=args.release, pack=args.pack, results=[], **revision_metadata())
    project = ROOT
    if args.world:
        if not args.source_report:parser.error('--world requires --source-report')
        source = (ROOT / args.source_report).resolve()
        if (ROOT / 'reports/player_survival_world').resolve() not in source.parents:parser.error('Only an owned survival report can be cloned')
        source_slot = json.loads((source / 'created_slot.json').read_text())['slot']
        if not isinstance(source_slot, str) or not source_slot.startswith('Survival_'):parser.error('Not an owned survival fixture')
        receipt = clone_once(Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds', source_slot, 'ClothingLoot_' + uuid.uuid4().hex[:12])
        record['clone'] = receipt
    if args.release:
        project = ROOT / '.build/clothing_loot_release'
        (project / 'addons/player_runtime/bin').mkdir(parents=True, exist_ok=True)
        (project / 'tests').mkdir(exist_ok=True)
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Clothing Loot Release Check"\n')
        library = 'player_runtime.windows.template_release.x86_64.dll'
        shutil.copy2(ROOT / 'addons/player_runtime/bin' / library, project / 'addons/player_runtime/bin' / library)
        extension = ROOT / 'addons/player_runtime/player_runtime.gdextension'
        (project / 'addons/player_runtime/player_runtime.gdextension').write_text(extension.read_text().replace('template_debug', 'template_release'))
        shutil.copy2(ROOT / 'tests/clothing_loot.gd', project / 'tests/clothing_loot.gd')
    if args.pack:
        record['native_sha256'] = verify_pack_native()
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        project = ROOT / 'dist'
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO();startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow = 4
        keywords['startupinfo'] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for job in (['loot', 'restore'] if args.world else ['native']):
            destination = folder / job;destination.mkdir()
            script = 'clothing_loot_world' if args.world else 'clothing_loot'
            driver = project / 'tests' / (script + '.gd')
            if args.world:
                (destination / 'world.json').write_text(json.dumps(receipt, indent=2) + '\n')
                if job == 'restore':shutil.copy2(folder / 'loot/loot.json', destination / 'loot.json')
            if args.pack:
                parent = destination / 'window_session_flow.gd';parent.write_bytes((ROOT / 'tests/window_session_flow.gd').read_bytes())
                driver = destination / 'driver.gd'
                driver.write_text((ROOT / 'tests/clothing_loot_world.gd').read_text().replace('res://tests/window_session_flow.gd', parent.as_posix()))
            command = [config.godot, '--path', str(project), '--log-file', str(destination / 'engine.log'), '--script', str(driver)]
            command += ['--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '30'] if args.world else ['--headless']
            if args.pack:command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
            command += ['--', '--session-evidence-dir=' + destination.as_posix()]
            if job == 'restore':command.append('--restore')
            result = execute(command, destination, 180 if args.world else 60, script.upper() + ' checks=', require_resource_budget=args.world)
            record['results'].append(dict(job=job, command=command, result=result))
            (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
            print(('PASS ' if result['passed'] else 'FAIL ') + str(destination), flush=True)
            if not result['passed']:return 1
    finally:
        subprocess.Popen = original
    return 0


if __name__ == '__main__':raise SystemExit(main())
