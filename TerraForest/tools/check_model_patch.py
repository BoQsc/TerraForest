# SPDX-License-Identifier: 0BSD
"""Check bounded static-model restoration and fresh-process persistence."""
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import shutil

from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true', help='Verify the explicit installed PCK and DLLs instead of isolated source variants')
    args = parser.parse_args()
    config, _ = parse_args([])
    folder = ROOT / 'reports/model_patch' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    rows = []
    native = verify_pack_native() if args.pack else None
    pack = ROOT / 'dist/TerraForest.pck'
    pack_hash = hashlib.sha256(pack.read_bytes()).hexdigest() if args.pack else None
    for variant in (('pack',) if args.pack else ('debug', 'release')):
        project = folder / variant
        addon = project / 'addons/structures'
        (addon / 'bin').mkdir(parents=True)
        (project / 'tests').mkdir()
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Model Patch Check"\n')
        library = f'structures.windows.template_{"debug" if args.pack else variant}.x86_64.dll'
        shutil.copy2(ROOT / 'addons/structures/bin' / library, addon / 'bin' / library)
        extension = (ROOT / 'addons/structures/structures.gdextension').read_text()
        if variant == 'release':
            extension = extension.replace('template_debug', 'template_release')
        (addon / 'structures.gdextension').write_text(extension)
        for suffix in ('.gd', '.gd.uid'):
            source = ROOT / 'tests' / ('model_patch' + suffix)
            if source.exists():
                shutil.copy2(source, project / 'tests' / source.name)
        for phase in ('create', 'reopen'):
            output = project / phase
            output.mkdir()
            source = str(ROOT / 'tests/model_patch.gd') if args.pack else 'res://tests/model_patch.gd'
            runtime = ['--path', str(ROOT / 'dist'), '--main-pack', str(pack)] if args.pack else ['--path', str(project)]
            command = [config.godot, '--headless', *runtime, '--script', source,
                       '--log-file', str(output / 'engine.log'), '--', '--model-patch-dir=' + str(project)]
            if phase == 'reopen':
                command.append('--reopen')
            result = execute(command, output, 90, 'MODEL_PATCH checks=')
            log = (output / 'console.log').read_text(encoding='utf-8', errors='replace')
            maximum = re.search(r'MODEL_PATCH_MAX bytes=(\d+) capture_us=(\d+) restore_us=(\d+)', log)
            assertions = re.search(r'MODEL_PATCH checks=(\d+) failures=(\d+)', log)
            rows.append(dict(variant=variant, phase=phase, command=command, result=result,
                             assertions=list(map(int, assertions.groups())) if assertions else None,
                             maximum=list(map(int, maximum.groups())) if maximum else None,
                             library_sha256=hashlib.sha256((addon / 'bin' / library).read_bytes()).hexdigest()))
    if args.pack:
        output = folder / 'horizon'
        output.mkdir()
        command = [config.godot, '--headless', '--path', str(ROOT / 'dist'), '--main-pack', str(pack),
                   '--script', str(ROOT / 'tests/model_horizon.gd'), '--log-file', str(output / 'engine.log'),
                   '--', '--view-output=' + str(output)]
        rows.append(dict(variant='pack', phase='horizon', command=command,
                         result=execute(command, output, 90, 'MODEL_HORIZON checks=')))
        if verify_pack_native() != native or hashlib.sha256(pack.read_bytes()).hexdigest() != pack_hash:
            raise RuntimeError('Installed native libraries or pack changed during verification')
    record = dict(passed=all(row['result']['passed'] for row in rows), runs=rows,
                  package_sha256=pack_hash, package_native=native,
                  scope='Bounded static placements only; not live doors, multi-owner location reset or gameplay performance.',
                  source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
                      'addons/structures/native/static_patch.cpp', 'addons/structures/native/static_batch.hpp',
                      'addons/structures/native/static_batch.cpp', 'tests/model_patch.gd', 'tests/model_horizon.gd', 'tools/check_model_patch.py')},
                  **revision_metadata())
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder))
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
