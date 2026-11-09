"""Run navigation physics contracts with release DLLs in an isolated project."""
# SPDX-License-Identifier: 0BSD
import datetime
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sampling', action='store_true')
    parser.add_argument('--navigation-profile', action='store_true')
    parser.add_argument('--tests', nargs='+', choices=['navigation_treads', 'regional_navigation', 'navigation_residency', 'zombie_step_guard', 'player_cottage_stairs', 'actor_route_sampling', 'actor_route_contract', 'navigation_support_cache', 'navigation_invalidation'])
    parser.add_argument('--baseline-native-ref', help='Use a committed world_runtime release DLL only in the isolated project for comparison')
    args = parser.parse_args()
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report = ROOT/'reports/regional_release'/stamp
    project = ROOT/'.build'/('regional_release_'+stamp)
    report.mkdir(parents=True)
    project.mkdir(parents=True)
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="TerraForest Navigation Release Check"\n')
    descriptors = []
    libraries = {}
    baseline_commit = None
    baseline_library = None
    if args.baseline_native_ref:
        baseline_commit = subprocess.check_output(['git', 'rev-parse', '--verify', args.baseline_native_ref+'^{commit}'], cwd=ROOT, text=True).strip()
        git_root = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], cwd=ROOT, text=True).strip())
        relative = (ROOT/'addons/world_runtime/bin/world_runtime.windows.template_release.x86_64.dll').relative_to(git_root).as_posix()
        baseline_library = subprocess.check_output(['git', 'show', baseline_commit+':'+relative], cwd=ROOT)
    for addon in ['world_runtime', 'player_runtime', 'structures', 'volumetric_terrain']:
        module = 'terrain_core' if addon == 'volumetric_terrain' else addon
        source = ROOT/'addons'/addon
        destination = project/'addons'/addon
        (destination/'bin').mkdir(parents=True)
        library = module+'.windows.template_release.x86_64.dll'
        shutil.copy2(source/'bin'/library, destination/'bin'/library)
        if addon == 'world_runtime' and baseline_library is not None:
            (destination/'bin'/library).write_bytes(baseline_library)
        libraries[str((source/'bin'/library).relative_to(ROOT))] = hashlib.sha256((destination/'bin'/library).read_bytes()).hexdigest()
        descriptor = (source/(module+'.gdextension')).read_text().replace('template_debug', 'template_release')
        if module == 'terrain_core':
            descriptor = descriptor.replace('terrain_core.windows.x86_64.dll', library)
        (destination/(module+'.gdextension')).write_text(descriptor)
        descriptors.append('res://addons/'+addon+'/'+module+'.gdextension')
    if not args.sampling or args.tests:
        shutil.copytree(ROOT/'addons/structures/prefabs', project/'addons/structures/prefabs')
        for catalog in ['furniture_catalog.gd', 'expansion_catalog.gd']:
            shutil.copy2(ROOT/'addons/structures'/catalog, project/'addons/structures'/catalog)
    (project/'.godot').mkdir()
    (project/'.godot/extension_list.cfg').write_text('\n'.join(descriptors)+'\n')
    (project/'tests').mkdir()
    outcomes = []
    tests = [('navigation_treads', 'NAVIGATION_TREADS checks='),
             ('regional_navigation', 'REGIONAL_NAVIGATION checks='),
             ('navigation_residency', 'NAVIGATION_RESIDENCY checks='),
             ('zombie_step_guard', 'ZOMBIE_STEP_GUARD PASS'),
             ('player_cottage_stairs', 'PLAYER_COTTAGE_STAIRS failures=0')]
    if args.sampling:
        tests = [('actor_route_sampling', 'ACTOR_ROUTE_SAMPLING checks='),
                 ('actor_route_contract', 'ACTOR_ROUTE_CONTRACT checks='),
                 ('navigation_support_cache', 'NAVIGATION_SUPPORT_CACHE checks='),
                 ('navigation_invalidation', 'NAVIGATION_INVALIDATION checks=')]
    if args.tests:
        markers = dict(tests)
        markers.update(zombie_step_guard='ZOMBIE_STEP_GUARD PASS', player_cottage_stairs='PLAYER_COTTAGE_STAIRS failures=0')
        tests = [(test, markers.get(test, test.upper()+' checks=')) for test in args.tests]
    record = dict(project=str(project), native_sha256=libraries,
                  baseline_world_runtime_commit=baseline_commit,
                  scope='Release DLL physics/API contracts in an isolated project; no exported-game or full-host release qualification.',
                  **revision_metadata())
    for test, marker in tests:
        source = ROOT/'tests'/(test+'.gd')
        shutil.copy2(source, project/'tests'/source.name)
        folder = report/test
        folder.mkdir()
        command = [str(config.godot), '--headless', '--path', str(project), '--max-fps', '60',
                   '--log-file', str(folder/'engine.log'), '--script', 'res://tests/'+source.name]
        if test == 'navigation_invalidation':command += ['--', '--native-only']
        if test == 'regional_navigation' and args.navigation_profile:command += ['--', '--navigation-profile']
        outcome = dict(test=test, command=command, test_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                       result=execute(command, folder, 120, marker))
        outcomes.append(outcome)
        result_file = project/'reports'/test/'result.json'
        if result_file.is_file():
            shutil.copy2(result_file, folder/'result.json')
        print(('PASS ' if outcome['result']['passed'] else 'FAIL ')+test, flush=True)
        record['outcomes'] = outcomes
        (report/'run.json').write_text(json.dumps(record, indent=2))
    print(report)
    return 0 if all(row['result']['passed'] for row in outcomes) else 1

if __name__ == '__main__':
    raise SystemExit(main())
