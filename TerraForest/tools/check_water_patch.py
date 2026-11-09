# SPDX-License-Identifier: 0BSD
"""Exercise bounded water restoration with isolated native owners and durable reopen."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import re
import shutil

from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata
from native_test_retention import release_copies


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true')
    args = parser.parse_args()
    config, _ = parse_args([])
    folder = ROOT / 'reports/water_patch' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    native = verify_pack_native() if args.pack else None
    pack = ROOT / 'dist/TerraForest.pck'
    pack_hash = hashlib.sha256(pack.read_bytes()).hexdigest() if args.pack else None
    runs = []
    copied_libraries = {}
    tests = ['water_patch', 'water_patch_contacts', 'water_static_editing', 'water_region_store', 'water_storage_snapshot', 'water_region_io', 'water_region_retirement', 'water_map_identity', 'water_region_transfer', 'ocean_residency', 'water_snapshot_cost']
    for variant in (('pack',) if args.pack else ('debug', 'release')):
        project = folder / variant
        project.mkdir()
        library_hash = None
        terrain_hash = None
        if not args.pack:
            (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Water Patch Check"\n')
            addon = project / 'addons/volumetric_water'
            (addon / 'bin').mkdir(parents=True)
            library = ROOT / 'addons/volumetric_water/bin' / f'volumetric_water.windows.template_{variant}.x86_64.dll'
            shutil.copy2(library, addon / 'bin' / library.name)
            library_hash = hashlib.sha256(library.read_bytes()).hexdigest()
            descriptor = (ROOT / 'addons/volumetric_water/volumetric_water.gdextension').read_text()
            if variant == 'release':
                descriptor = descriptor.replace('template_debug', 'template_release')
            (addon / 'volumetric_water.gdextension').write_text(descriptor)
            (project / '.godot').mkdir()
            (project / '.godot/extension_list.cfg').write_text('res://addons/volumetric_water/volumetric_water.gdextension\nres://addons/volumetric_terrain/terrain_core.gdextension\n')
            terrain = project / 'addons/volumetric_terrain'
            (terrain / 'bin').mkdir(parents=True)
            terrain_name = 'terrain_core.windows.x86_64.dll' if variant == 'debug' else 'terrain_core.windows.template_release.x86_64.dll'
            terrain_library = ROOT / 'addons/volumetric_terrain/bin' / terrain_name
            shutil.copy2(terrain_library, terrain / 'bin' / terrain_name)
            terrain_hash = hashlib.sha256(terrain_library.read_bytes()).hexdigest()
            copied_libraries[project] = {addon / 'bin' / library.name: library_hash, terrain / 'bin' / terrain_name: terrain_hash}
            terrain_descriptor = (ROOT / 'addons/volumetric_terrain/terrain_core.gdextension').read_text()
            if variant == 'release':
                terrain_descriptor = terrain_descriptor.replace('terrain_core.windows.x86_64.dll', terrain_name)
            (terrain / 'terrain_core.gdextension').write_text(terrain_descriptor)
            for name in ['mesh_codec.gd', 'mesh_codec.gd.uid']:
                shutil.copy2(ROOT / 'addons/volumetric_terrain' / name, terrain / name)
        runtime = ['--path', str(ROOT / 'dist'), '--main-pack', str(pack)] if args.pack else ['--path', str(project)]
        phases = [('create', 'water_patch'), ('reopen', 'water_patch'), *[(name, name) for name in tests[1:]]]
        for phase, test in phases:
            output = project / phase
            output.mkdir()
            source = ROOT / 'tests' / (test + '.gd')
            driver = output / source.name
            fixture_path = output.as_posix()
            for name in tests:
                script = (ROOT / 'tests' / (name + '.gd')).read_text()
                script = script.replace('res://tests/', fixture_path + '/')
                script = script.replace('res://reports', fixture_path + '/reports')
                script = script.replace('user://', fixture_path + '/user/')
                (output / (name + '.gd')).write_text(script)
            marker = test.upper() + (' checks=' if test in ('water_patch', 'water_patch_contacts') else ' failures=0')
            command = [config.godot, '--headless', *runtime, '--script', str(driver), '--log-file', str(output / 'engine.log'), '--', '--water-patch-dir=' + str(project)]
            if phase == 'reopen':
                command.append('--reopen')
            result = execute(command, output, 150, marker)
            log = (output / 'console.log').read_text(encoding='utf-8', errors='replace')
            match = re.search(test.upper() + r' checks=(\d+) failures=(\d+)', log)
            counts = list(map(int, match.groups())) if match else None
            if test in ('water_patch', 'water_patch_contacts'):
                result['passed'] = result['passed'] and counts is not None and counts[0] > 0 and counts[1] == 0
            timing = re.search(r'WATER_PATCH_MAX bytes=(\d+) capture_us=(\d+) restore_us=(\d+)', log)
            dry_timing = re.search(r'WATER_PATCH_DRY bytes=(\d+) capture_us=(\d+) restore_us=(\d+)', log)
            runs.append(dict(variant=variant, phase=phase, command=command, result=result, assertions=counts,
                             library_sha256=library_hash, terrain_library_sha256=terrain_hash,
                             source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                             timing=list(map(int, timing.groups())) if timing else None,
                             dry_timing=list(map(int, dry_timing.groups())) if dry_timing else None))
            if not result['passed']:
                break
    if args.pack and (verify_pack_native() != native or hashlib.sha256(pack.read_bytes()).hexdigest() != pack_hash):
        raise RuntimeError('Installed package changed during verification')
    record = dict(passed=all(row['result']['passed'] for row in runs), runs=runs,
                  pack_sha256=pack_hash, native_sha256=native,
                  scope='Selected water amounts/vacancies and existing publication/storage, not full live POI reset.',
                  sources={str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in [*[ROOT / 'tests' / (name + '.gd') for name in tests], ROOT / 'tools/check_water_patch.py',
                                        ROOT / 'addons/volumetric_water/native/water_patch.cpp',
                                        ROOT / 'addons/volumetric_water/native/regional_water.hpp',
                                        ROOT / 'addons/volumetric_water/native/snapshot_array.hpp',
                                        ROOT / 'addons/volumetric_water/native/regional_water.cpp']},
                  **revision_metadata())
    record['native_copy_retention'] = release_copies(copied_libraries, record['passed'])
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
