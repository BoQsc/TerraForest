# SPDX-License-Identifier: 0BSD
"""Verify native corpse ownership, bounded reset and legacy storage in isolated projects."""
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
    choices = parser.add_mutually_exclusive_group()
    choices.add_argument('--pack', action='store_true')
    choices.add_argument('--pending-debug', action='store_true')
    args = parser.parse_args()
    config, _ = parse_args([])
    folder = ROOT / 'reports/corpse_patch' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    pack = ROOT / 'dist/TerraForest.pck'
    native = verify_pack_native() if args.pack else None
    pack_hash = hashlib.sha256(pack.read_bytes()).hexdigest() if args.pack else None
    rows = []
    variants = ('pack',) if args.pack else ('pending_debug',) if args.pending_debug else ('debug', 'release')
    for variant in variants:
        project = folder / variant
        project.mkdir()
        library_hash = None
        if not args.pack:
            (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Corpse Patch Check"\n')
            addon = project / 'addons/player_runtime'
            (addon / 'bin').mkdir(parents=True)
            name = f'player_runtime.windows.template_{"debug" if args.pending_debug else variant}.x86_64.dll'
            library = ROOT / '.build/native/player_runtime/template_debug/player_runtime.pending.dll' if args.pending_debug else ROOT / 'addons/player_runtime/bin' / name
            shutil.copy2(library, addon / 'bin' / name)
            library_hash = hashlib.sha256(library.read_bytes()).hexdigest()
            descriptor = (ROOT / 'addons/player_runtime/player_runtime.gdextension').read_text()
            if variant == 'release':
                descriptor = descriptor.replace('template_debug', 'template_release')
            (addon / 'player_runtime.gdextension').write_text(descriptor)
        runtime = ['--path', str(ROOT / 'dist'), '--main-pack', str(pack)] if args.pack else ['--path', str(project)]
        phases = [('create', 'corpse_patch', 'CORPSE_PATCH checks='), ('reopen', 'corpse_patch', 'CORPSE_PATCH checks='),
                  ('clothing_loot', 'clothing_loot', 'CLOTHING_LOOT checks='), ('container_patch', 'container_patch', 'CONTAINER_PATCH checks='),
                  ('container_locks', 'container_locks', 'CONTAINER_LOCKS {'), ('container_capacity', 'container_capacity', 'CONTAINER_CAPACITY failures=0')]
        for phase, test, marker in phases:
            output = project / phase
            output.mkdir()
            source = ROOT / 'tests' / (test + '.gd')
            driver = output / source.name
            driver.write_text(source.read_text().replace('res://reports', str(output).replace('\\', '/')))
            extra = ['--corpse-patch-dir=' + str(project)]
            if phase == 'reopen':
                extra.append('--reopen')
            command = [config.godot, '--headless', *runtime, '--script', str(driver), '--log-file', str(output / 'engine.log'), '--', *extra]
            result = execute(command, output, 90, marker)
            log = (output / 'console.log').read_text(encoding='utf-8', errors='replace')
            assertions = re.search(r'checks=(\d+) failures=(\d+)', log)
            assertion_values = list(map(int, assertions.groups())) if assertions else None
            if test == 'container_locks':
                match = re.search(r'CONTAINER_LOCKS (\{[^\n]+\})', log)
                values = json.loads(match.group(1)) if match else {}
                assertion_values = [values.get('checks', 0), values.get('failures', 1)]
                result['passed'] = result['passed'] and assertion_values[0] > 0 and assertion_values[1] == 0
            timing = re.search(r'CORPSE_PATCH_MAX bytes=(\d+) capture_us=(\d+) clear_us=(\d+) restore_us=(\d+)', log)
            rows.append(dict(variant=variant, phase=phase, command=command, result=result, library_sha256=library_hash,
                             assertions=assertion_values,
                             timing=list(map(int, timing.groups())) if timing else None,
                             source_sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
    if args.pack and (verify_pack_native() != native or hashlib.sha256(pack.read_bytes()).hexdigest() != pack_hash):
        raise RuntimeError('Installed package/native identity changed during verification')
    record = dict(passed=all(row['result']['passed'] for row in rows), runs=rows, package_sha256=pack_hash, package_native=native,
                  scope='Corpse ownership and bounded body/loot restoration, not live multi-owner location reset.',
                  source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
                      'addons/player_runtime/native/corpses.hpp', 'addons/player_runtime/native/corpses.cpp', 'addons/player_runtime/native/corpse_patch.cpp',
                      'addons/player_runtime/native/containers.cpp', 'addons/player_runtime/native/container_patch.cpp', 'addons/player_runtime/corpse_loot.gd',
                      'tests/corpse_patch.gd', 'tools/check_corpse_patch.py')}, **revision_metadata())
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder))
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
