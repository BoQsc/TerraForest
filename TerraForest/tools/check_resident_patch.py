# SPDX-License-Identifier: 0BSD
"""Check scoped authored-resident reset and reopen in isolated native projects."""
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
    folder = ROOT / 'reports/resident_patch' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    pack = ROOT / 'dist/TerraForest.pck'
    native = verify_pack_native() if args.pack else None
    pack_hash = hashlib.sha256(pack.read_bytes()).hexdigest() if args.pack else None
    rows = []
    for variant in (('pack',) if args.pack else ('debug', 'release')):
        project = folder / variant
        project.mkdir()
        library_hash = None
        if not args.pack:
            (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Resident Patch Check"\n')
            addon = project / 'addons/world_runtime'
            (addon / 'bin').mkdir(parents=True)
            library = ROOT / 'addons/world_runtime/bin' / f'world_runtime.windows.template_{variant}.x86_64.dll'
            shutil.copy2(library, addon / 'bin' / library.name)
            library_hash = hashlib.sha256(library.read_bytes()).hexdigest()
            descriptor = (ROOT / 'addons/world_runtime/world_runtime.gdextension').read_text()
            if variant == 'release':
                descriptor = descriptor.replace('template_debug', 'template_release')
            (addon / 'world_runtime.gdextension').write_text(descriptor)
        runtime = ['--path', str(ROOT / 'dist'), '--main-pack', str(pack)] if args.pack else ['--path', str(project)]
        for phase in ('create', 'reopen', 'zombie_population'):
            output = project / phase
            output.mkdir()
            source = ROOT / 'tests' / ('zombie_population.gd' if phase == 'zombie_population' else 'resident_patch.gd')
            driver = output / source.name
            driver.write_text(source.read_text().replace('res://reports', str(output).replace('\\', '/')))
            extra = ['--population-output=' + str(output)] if phase == 'zombie_population' else ['--resident-patch-dir=' + str(project)]
            if phase == 'reopen':
                extra.append('--reopen')
            marker = 'ZOMBIE_POPULATION checks=' if phase == 'zombie_population' else 'RESIDENT_PATCH checks='
            command = [config.godot, '--headless', *runtime, '--script', str(driver), '--log-file', str(output / 'engine.log'), '--', *extra]
            result = execute(command, output, 90, marker)
            log = (output / 'console.log').read_text(encoding='utf-8', errors='replace')
            assertions = re.search(r'checks=(\d+) failures=(\d+)', log)
            timing = re.search(r'RESIDENT_PATCH_MAX bytes=(\d+) capture_us=(\d+) restore_us=(\d+) buckets=(\d+)', log)
            rows.append(dict(variant=variant, phase=phase, command=command, result=result, library_sha256=library_hash,
                             assertions=list(map(int, assertions.groups())) if assertions else None,
                             timing=list(map(int, timing.groups())) if timing else None,
                             driver_sha256=hashlib.sha256(driver.read_bytes()).hexdigest()))
    if args.pack and (verify_pack_native() != native or hashlib.sha256(pack.read_bytes()).hexdigest() != pack_hash):
        raise RuntimeError('Installed package/native identity changed during verification')
    record = dict(passed=all(row['result']['passed'] for row in rows), runs=rows, package_sha256=pack_hash, package_native=native,
                  scope='Authored resident data, local spatial membership and fresh-process restoration; not live actor/corpse orchestration or gameplay quest reset.',
                  source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
                      'addons/world_runtime/native/zombie_population.hpp', 'addons/world_runtime/native/resident_patch.cpp',
                      'tests/resident_patch.gd', 'tools/check_resident_patch.py')}, **revision_metadata())
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder))
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
