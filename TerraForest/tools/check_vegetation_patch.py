# SPDX-License-Identifier: 0BSD
"""Check bounded vegetation reset storage with isolated debug/release native owners."""
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
    folder = ROOT / 'reports/vegetation_patch' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    native = verify_pack_native() if args.pack else None
    pack = ROOT / 'dist/TerraForest.pck'
    pack_hash = hashlib.sha256(pack.read_bytes()).hexdigest() if args.pack else None
    runs = []
    for variant in (('pack',) if args.pack else ('debug', 'release')):
        project = folder / variant
        project.mkdir()
        library_hash = None
        if not args.pack:
            (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Vegetation Patch Check"\n')
            addon = project / 'addons/vegetation_runtime'
            (addon / 'bin').mkdir(parents=True)
            name = f'vegetation_runtime.windows.template_{variant}.x86_64.dll'
            library = ROOT / 'addons/vegetation_runtime/bin' / name
            shutil.copy2(library, addon / 'bin' / name)
            library_hash = hashlib.sha256(library.read_bytes()).hexdigest()
            descriptor = (ROOT / 'addons/vegetation_runtime/vegetation_runtime.gdextension').read_text()
            if variant == 'release':
                descriptor = descriptor.replace('template_debug', 'template_release')
            (addon / 'vegetation_runtime.gdextension').write_text(descriptor)
        runtime = ['--path', str(ROOT / 'dist'), '--main-pack', str(pack)] if args.pack else ['--path', str(project)]
        phases = [('create', 'vegetation_patch', 'VEGETATION_PATCH checks='),
                  ('reopen', 'vegetation_patch', 'VEGETATION_PATCH checks='),
                  ('state', 'ground_cover_state', 'GROUND_COVER_STATE ')]
        if args.pack:
            phases += [('harvest_publication', 'harvest_state', 'HARVEST_STATE '),
                       ('harvest_persistence', 'harvest_persistence', 'HARVEST_PERSISTENCE ')]
        for phase, test, marker in phases:
            output = project / phase
            output.mkdir()
            source = ROOT / 'tests' / (test + '.gd')
            driver = output / source.name
            driver.write_text(source.read_text().replace('res://reports', str(output).replace('\\', '/')))
            command = [config.godot, '--headless', *runtime, '--script', str(driver), '--log-file', str(output / 'engine.log'), '--', '--vegetation-patch-dir=' + str(project)]
            if phase == 'reopen':
                command.append('--reopen')
            result = execute(command, output, 120, marker)
            log = (output / 'console.log').read_text(encoding='utf-8', errors='replace')
            match = re.search(r'VEGETATION_PATCH checks=(\d+) failures=(\d+)', log)
            counts = list(map(int, match.groups())) if match else [0, 1]
            if test != 'vegetation_patch':
                match = re.search(re.escape(marker) + r'(\{[^\n]+\})', log)
                values = json.loads(match.group(1)) if match else {}
                counts = [values.get('checks', 0), values.get('failures', 1)]
            result['passed'] = result['passed'] and counts[0] > 0 and counts[1] == 0
            timing = re.search(r'VEGETATION_PATCH_MAX bytes=(\d+) capture_us=(\d+) restore_us=(\d+)', log)
            runs.append(dict(variant=variant, phase=phase, command=command, result=result, assertions=counts,
                             library_sha256=library_hash, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                             timing=list(map(int, timing.groups())) if timing else None))
            if not result['passed']:
                break
    if args.pack and (verify_pack_native() != native or hashlib.sha256(pack.read_bytes()).hexdigest() != pack_hash):
        raise RuntimeError('Installed package changed during verification')
    record = dict(passed=all(row['result']['passed'] for row in runs), runs=runs,
                  pack_sha256=pack_hash, native_sha256=native,
                  scope='Selected vegetation state and fresh-process reset, not complete live POI reset.',
                  sources={str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in [ROOT / 'tests/vegetation_patch.gd', ROOT / 'tools/check_vegetation_patch.py',
                                        *sorted((ROOT / 'addons/vegetation_runtime/native').glob('*patch*')),
                                        ROOT / 'addons/vegetation_runtime/native/ground_state.hpp',
                                        ROOT / 'addons/vegetation_runtime/native/harvest_state.hpp']},
                  **revision_metadata())
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
