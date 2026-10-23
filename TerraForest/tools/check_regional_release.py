"""Run navigation physics contracts with release DLLs in an isolated project."""
# SPDX-License-Identifier: 0BSD
import datetime
import hashlib
import json
import shutil
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

def main():
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report = ROOT/'reports/regional_release'/stamp
    project = ROOT/'.build'/('regional_release_'+stamp)
    report.mkdir(parents=True)
    project.mkdir(parents=True)
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="TerraForest Navigation Release Check"\n')
    descriptors = []
    libraries = {}
    for addon in ['world_runtime', 'player_runtime', 'structures', 'volumetric_terrain']:
        module = 'terrain_core' if addon == 'volumetric_terrain' else addon
        source = ROOT/'addons'/addon
        destination = project/'addons'/addon
        (destination/'bin').mkdir(parents=True)
        library = module+'.windows.template_release.x86_64.dll'
        shutil.copy2(source/'bin'/library, destination/'bin'/library)
        libraries[str((source/'bin'/library).relative_to(ROOT))] = hashlib.sha256((source/'bin'/library).read_bytes()).hexdigest()
        descriptor = (source/(module+'.gdextension')).read_text().replace('template_debug', 'template_release')
        if module == 'terrain_core':
            descriptor = descriptor.replace('terrain_core.windows.x86_64.dll', library)
        (destination/(module+'.gdextension')).write_text(descriptor)
        descriptors.append('res://addons/'+addon+'/'+module+'.gdextension')
    shutil.copytree(ROOT/'addons/structures/prefabs', project/'addons/structures/prefabs')
    shutil.copy2(ROOT/'addons/structures/furniture_catalog.gd', project/'addons/structures/furniture_catalog.gd')
    (project/'.godot').mkdir()
    (project/'.godot/extension_list.cfg').write_text('\n'.join(descriptors)+'\n')
    (project/'tests').mkdir()
    outcomes = []
    tests = [('regional_navigation', 'REGIONAL_NAVIGATION checks=14 failures=0'),
             ('navigation_residency', 'NAVIGATION_RESIDENCY checks=11 failures=0'),
             ('zombie_step_guard', 'ZOMBIE_STEP_GUARD PASS'),
             ('player_cottage_stairs', 'PLAYER_COTTAGE_STAIRS failures=0')]
    record = dict(project=str(project), native_sha256=libraries,
                  scope='Release DLL physics/API contracts in an isolated project; no exported-game or full-host release qualification.',
                  **revision_metadata())
    for test, marker in tests:
        source = ROOT/'tests'/(test+'.gd')
        shutil.copy2(source, project/'tests'/source.name)
        folder = report/test
        folder.mkdir()
        command = [str(config.godot), '--headless', '--path', str(project), '--max-fps', '60',
                   '--log-file', str(folder/'engine.log'), '--script', 'res://tests/'+source.name]
        outcome = dict(test=test, command=command, test_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                       result=execute(command, folder, 120, marker))
        outcomes.append(outcome)
        print(('PASS ' if outcome['result']['passed'] else 'FAIL ')+test, flush=True)
        record['outcomes'] = outcomes
        (report/'run.json').write_text(json.dumps(record, indent=2))
    print(report)
    return 0 if all(row['result']['passed'] for row in outcomes) else 1

if __name__ == '__main__':
    raise SystemExit(main())
