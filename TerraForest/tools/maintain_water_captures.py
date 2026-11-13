# SPDX-License-Identifier: 0BSD
"""Cold-retain completed barrel captures; preserve two ready runs and all logs."""
import argparse
import json
from pathlib import Path

from development_storage import admit
from maintain_performance_artifacts import ROOT, no_game_processes, owned_lease
from retained_artifacts import Store, archive, confined, digest, retire

NAMES = {name + '.png' for name in (
    'barrel_before', 'barrel_after', 'barrel_after_underwater', 'shore_before',
    'shore_after', 'shore_underwater', 'mining_underwater', 'deposition_above',
    'deposition_underwater')}
NAMES.add('post_blast.water')


def candidates(root=ROOT):
    ready = []
    for manifest in sorted((root / 'reports/checks').glob('*/run.json')):
        run = json.loads(manifest.read_text(encoding='utf-8'))
        if run.get('result', {}).get('exit_code') is None:
            continue
        command = run.get('command', [])
        if '--script' not in command:
            continue
        script = command[command.index('--script') + 1]
        if script not in ('res://tests/water_barrel_world.gd', str(root / 'tests/water_barrel_world.gd')):
            continue
        folder = confined(manifest.parent, root / 'reports/checks')
        if '--check-evidence-dir=' + str(folder) not in command:
            continue
        if (folder / 'captures.archive.json').exists():
            continue
        if any((folder / pin).exists() for pin in ('.retain', 'RETAIN_READY')):
            continue
        if any((folder / name).is_file() for name in NAMES):
            ready.append(folder)
    return ready[:-2]


def maintain(apply=False, root=ROOT):
    selected = candidates(root)
    result = dict(candidates=[str(p) for p in selected], reclaimed_bytes=0, manifests=[])
    if not apply or not selected:
        return result
    admit(root, report_bytes=1024 * 1024, world_bytes=0)
    no_game_processes()
    with owned_lease(root / 'reports/retained_artifacts/writer', root):
        store = Store(root / 'reports/retained_artifacts/chunks')
        for folder in selected:
            no_game_processes()
            members = sorted(name for name in NAMES if (folder / name).is_file())
            record = archive(folder, members, folder / 'captures.archive.json', store,
                             dict(kind='completed-water-captures', run_sha256=digest(folder / 'run.json')))
            result['reclaimed_bytes'] += retire(record, store, folder)
            result['manifests'].append(str(folder / 'captures.archive.json'))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    print(json.dumps(maintain(parser.parse_args().apply), indent=2))
