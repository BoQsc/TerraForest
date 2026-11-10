# SPDX-License-Identifier: 0BSD
"""Verify native location baseline durability without opening player saves."""
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
from development_storage import admit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true')
    args = parser.parse_args()
    admit(ROOT)
    config, _ = parse_args([])
    folder = ROOT / 'reports/location_baseline' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    pack = ROOT / 'dist/TerraForest.pck'
    native = verify_pack_native() if args.pack else None
    pack_hash = hashlib.sha256(pack.read_bytes()).hexdigest() if args.pack else None
    rows = []
    copied_libraries = {}
    for variant in (('pack',) if args.pack else ('debug', 'release')):
        project = folder / variant
        project.mkdir()
        libraries = {}
        if not args.pack:
            (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Location Baseline Check"\n')
            extensions = []
            copied_libraries[project] = {}
            for name in ('world_runtime', 'volumetric_terrain', 'volumetric_water'):
                addon = project / 'addons' / name
                (addon / 'bin').mkdir(parents=True)
                base = 'terrain_core' if name == 'volumetric_terrain' else name
                library_name = 'terrain_core.windows.x86_64.dll' if name == 'volumetric_terrain' and variant == 'debug' else f'{base}.windows.template_{variant}.x86_64.dll'
                library = ROOT / 'addons' / name / 'bin' / library_name
                shutil.copy2(library, addon / 'bin' / library_name)
                libraries[name] = hashlib.sha256(library.read_bytes()).hexdigest()
                copied_libraries[project][addon / 'bin' / library_name] = libraries[name]
                descriptor = (ROOT / 'addons' / name / (base + '.gdextension')).read_text()
                if variant == 'release':
                    descriptor = descriptor.replace('template_debug', 'template_release').replace('terrain_core.windows.x86_64.dll', library_name)
                (addon / (base + '.gdextension')).write_text(descriptor)
                extensions.append('res://addons/' + name + '/' + base + '.gdextension')
            (project / '.godot').mkdir()
            (project / '.godot/extension_list.cfg').write_text('\n'.join(extensions) + '\n')
            for name in ('mesh_codec.gd', 'mesh_codec.gd.uid'):
                shutil.copy2(ROOT / 'addons/volumetric_terrain' / name, project / 'addons/volumetric_terrain' / name)
            for name in ('world_persistence.gd', 'world_persistence.gd.uid'):
                shutil.copy2(ROOT / 'addons/world_runtime' / name, project / 'addons/world_runtime' / name)
        runtime = ['--path', str(ROOT / 'dist'), '--main-pack', str(pack)] if args.pack else ['--path', str(project)]
        for phase, test in [('create', 'location_baseline'), ('reopen', 'location_baseline'), ('publication', 'location_baseline_publication'), ('publication_reopen', 'location_baseline_publication'), ('archive', 'world_archive')]:
            output = project / phase
            output.mkdir()
            (output / 'user').mkdir()
            source = ROOT / 'tests' / (test + '.gd')
            driver = output / source.name
            script = source.read_text().replace('user://', output.as_posix() + '/user/').replace('res://reports', output.as_posix() + '/reports')
            driver.write_text(script)
            marker = 'LOCATION_PUBLICATION checks=' if test == 'location_baseline_publication' else 'LOCATION_BASELINE checks=' if test == 'location_baseline' else 'PASS save lease released for next owner'
            command = [config.godot, '--headless', *runtime, '--script', str(driver), '--log-file', str(output / 'engine.log'), '--', '--baseline-dir=' + str(project)]
            if phase.endswith('reopen'):
                command.append('--reopen')
            result = execute(command, output, 150, marker)
            log = (output / 'console.log').read_text(encoding='utf-8', errors='replace')
            match = re.search(r'LOCATION_(?:BASELINE|PUBLICATION) checks=(\d+) failures=(\d+)', log)
            assertions = list(map(int, match.groups())) if match else None
            if test.startswith('location_baseline'):
                result['passed'] = result['passed'] and assertions is not None and assertions[0] > 0 and assertions[1] == 0
            else:
                receipt = output / 'reports/world_archive.json'
                details = json.loads(receipt.read_text()) if receipt.is_file() else {}
                assertions = [len(details.get('checks', [])), details.get('failures', -1)]
                result['passed'] = result['passed'] and assertions[0] > 0 and assertions[1] == 0
            timing = re.search(r'LOCATION_BASELINE_TIMING manifest_bytes=(\d+) capture_us=(\d+) blob_bytes=(\d+) publish_us=(\d+) read_us=(\d+)', log)
            rows.append(dict(variant=variant, phase=phase, result=result, assertions=assertions, command=command,
                             libraries=libraries, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                             timing=list(map(int, timing.groups())) if timing else None))
            if not result['passed']:
                break
    if args.pack and (verify_pack_native() != native or hashlib.sha256(pack.read_bytes()).hexdigest() != pack_hash):
        raise RuntimeError('Installed package changed during verification')
    record = dict(passed=all(row['result']['passed'] for row in rows), runs=rows, native_sha256=native, pack_sha256=pack_hash,
                  scope='Immutable world/location-bound opaque patches, compound persistence provider, selected-reference publication/recovery. No generation owner capture, live reset transaction or marker/E activation.',
                  sources={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
                      'addons/world_runtime/native/location_baseline.cpp', 'addons/world_runtime/native/location_baseline.hpp',
                      'addons/world_runtime/native/world_publication.cpp', 'addons/world_runtime/world_persistence.gd',
                      'addons/world_runtime/generate_world_task.gd', 'addons/world_runtime/native/register_types.cpp',
                      'tests/location_baseline.gd', 'tests/location_baseline_publication.gd', 'tools/check_location_baseline.py')}, **revision_metadata())
    record['native_copy_retention'] = release_copies(copied_libraries, record['passed'])
    record['passed'] = record['passed'] and not record['native_copy_retention']['errors']
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
