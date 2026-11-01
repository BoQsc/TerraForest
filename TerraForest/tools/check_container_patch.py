# SPDX-License-Identifier: 0BSD
"""Validate scoped container restoration in isolated debug/release builds."""
from datetime import datetime, timezone
import hashlib
import json
import shutil

from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    config, _ = parse_args([])
    folder = ROOT / 'reports/container_patch' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    rows = []
    for variant in ('debug', 'release'):
        project = folder / variant
        addon = project / 'addons/player_runtime'
        (addon / 'bin').mkdir(parents=True)
        (project / 'tests').mkdir()
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Container Patch Check"\n')
        library = f'player_runtime.windows.template_{variant}.x86_64.dll'
        shutil.copy2(ROOT / 'addons/player_runtime/bin' / library, addon / 'bin' / library)
        extension = (ROOT / 'addons/player_runtime/player_runtime.gdextension').read_text()
        if variant == 'release':
            extension = extension.replace('template_debug', 'template_release')
        (addon / 'player_runtime.gdextension').write_text(extension)
        for name in ('container_patch.gd', 'container_patch.gd.uid'):
            if (ROOT / 'tests' / name).exists():
                shutil.copy2(ROOT / 'tests' / name, project / 'tests' / name)
        command = [config.godot, '--headless', '--path', str(project), '--script', 'res://tests/container_patch.gd', '--log-file', str(project / 'engine.log')]
        result = execute(command, project, 90, 'CONTAINER_PATCH checks=')
        rows.append(dict(variant=variant, command=command, result=result,
                         library_sha256=hashlib.sha256((addon / 'bin' / library).read_bytes()).hexdigest()))
    record = dict(passed=all(row['result']['passed'] for row in rows), variants=rows,
                  scope='Scoped inventory and lock restoration only, not model/corpse ownership or gameplay quest reset.', **revision_metadata())
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder))
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
