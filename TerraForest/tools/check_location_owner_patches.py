# SPDX-License-Identifier: 0BSD
"""Verify bounded hinge and durability restoration without touching player worlds."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import re
import shutil

from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true')
    args = parser.parse_args()
    config, _ = parse_args([])
    folder = ROOT / 'reports/location_owner_patches' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    pack = ROOT / 'dist/TerraForest.pck'
    native = verify_pack_native() if args.pack else None
    pack_hash = hashlib.sha256(pack.read_bytes()).hexdigest() if args.pack else None
    rows = []
    for variant in (('pack',) if args.pack else ('debug', 'release')):
        project = folder / variant
        project.mkdir()
        libraries = {}
        if not args.pack:
            (project / 'tests').mkdir()
            (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Location Owner Patch Check"\n')
            for name in ('structures', 'player_runtime'):
                addon = project / 'addons' / name
                (addon / 'bin').mkdir(parents=True)
                library = ROOT / 'addons' / name / 'bin' / f'{name}.windows.template_{variant}.x86_64.dll'
                shutil.copy2(library, addon / 'bin' / library.name)
                libraries[name] = hashlib.sha256(library.read_bytes()).hexdigest()
                descriptor = (ROOT / 'addons' / name / f'{name}.gdextension').read_text()
                if variant == 'release':
                    descriptor = descriptor.replace('template_debug', 'template_release')
                (addon / f'{name}.gdextension').write_text(descriptor)
            for suffix in ('.gd', '.gd.uid'):
                source = ROOT / 'tests' / ('location_owner_patches' + suffix)
                if source.exists():
                    shutil.copy2(source, project / 'tests' / source.name)
        for phase in ('create', 'reopen'):
            output = project / phase
            output.mkdir()
            runtime = ['--path', str(ROOT / 'dist'), '--main-pack', str(pack)] if args.pack else ['--path', str(project)]
            source = str(ROOT / 'tests/location_owner_patches.gd') if args.pack else 'res://tests/location_owner_patches.gd'
            command = [config.godot, '--headless', *runtime, '--script', source, '--log-file', str(output / 'engine.log'),
                       '--', '--owner-patch-dir=' + str(project)]
            if phase == 'reopen':
                command.append('--reopen')
            result = execute(command, output, 90, 'LOCATION_OWNER_PATCHES checks=')
            log = (output / 'console.log').read_text(encoding='utf-8', errors='replace')
            assertions = re.search(r'LOCATION_OWNER_PATCHES checks=(\d+) failures=(\d+)', log)
            timings = re.findall(r'(DOOR|DAMAGE)_PATCH_MAX bytes=(\d+) capture_us=(\d+) restore_us=(\d+)', log)
            rows.append(dict(variant=variant, phase=phase, command=command, result=result, libraries=libraries,
                             assertions=list(map(int, assertions.groups())) if assertions else None,
                             timings={name: list(map(int, values)) for name, *values in timings}))
        regressions = [('combat_state', 'COMBAT_STATE checks=', ['--native-only']),
                       ('harvest_hit_native', 'HARVEST_HIT_NATIVE checks=', []),
                       ('container_patch', 'CONTAINER_PATCH checks=', [])]
        if args.pack:
            regressions += [('door_animation', 'DOOR_ANIMATION checks=', []),
                            ('door_component', 'DOOR_COMPONENT failures=0', []),
                            ('attack_durability', 'ATTACK_DURABILITY checks=', [])]
        for name, marker, extra in regressions:
            output = project / name
            output.mkdir()
            source = ROOT / 'tests' / (name + '.gd')
            driver = output / source.name
            text = source.read_text()
            if args.pack:
                text = text.replace('res://reports', str(output).replace('\\', '/'))
            driver.write_text(text)
            command = [config.godot, '--headless', *runtime, '--script', str(driver),
                       '--log-file', str(output / 'engine.log'), '--', *extra]
            result = execute(command, output, 90, marker)
            log = (output / 'console.log').read_text(encoding='utf-8', errors='replace')
            assertions = re.search(r'checks=(\d+) failures=(\d+)', log)
            rows.append(dict(variant=variant, phase=name, command=command, result=result, libraries=libraries,
                             assertions=list(map(int, assertions.groups())) if assertions else None,
                             source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                             driver_sha256=hashlib.sha256(driver.read_bytes()).hexdigest()))
    if args.pack and (verify_pack_native() != native or hashlib.sha256(pack.read_bytes()).hexdigest() != pack_hash):
        raise RuntimeError('Installed package/native identity changed during verification')
    record = dict(passed=all(row['result']['passed'] for row in rows), runs=rows,
                  package_sha256=pack_hash, package_native=native,
                  scope='Selected hinge/damage states and composed model restore; not complete multi-owner gameplay reset or frame-pacing qualification.',
                  source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
                      'addons/structures/native/hinged_doors.cpp', 'addons/structures/native/hinged_doors.hpp', 'addons/structures/native/door_patch.cpp',
                      'addons/player_runtime/native/durability.cpp', 'addons/player_runtime/native/durability.hpp', 'addons/player_runtime/native/durability_patch.cpp',
                      'addons/player_runtime/native/combat_state.cpp', 'addons/player_runtime/native/combat_state.hpp',
                      'tests/location_owner_patches.gd', 'tools/check_location_owner_patches.py')}, **revision_metadata())
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder))
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
