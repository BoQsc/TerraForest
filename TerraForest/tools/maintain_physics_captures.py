# SPDX-License-Identifier: 0BSD
"""Cold-retain receipt-owned physics cadence, keeping two ordinary ready runs."""
import argparse
import json

from development_storage import admit
from maintain_performance_artifacts import ROOT, no_game_processes, owned_lease
from retained_artifacts import Store, archive, confined, digest, retire


def candidates(root=ROOT):
    ready = []
    for manifest in sorted((root / 'reports/checks').glob('*/run.json')):
        run = json.loads(manifest.read_text(encoding='utf-8'))
        command = run.get('command', [])
        folder = confined(manifest.parent, root / 'reports/checks')
        if (run.get('result', {}).get('exit_code') is None or '--script' not in command
                or command[command.index('--script') + 1] != 'res://tests/physics_residency_world.gd'
                or f'--check-evidence-dir={folder}' not in command):
            continue
        if any((folder / pin).exists() for pin in ('.retain', 'RETAIN_READY')):
            continue
        if (folder / 'physics_residency.json').is_file():
            ready.append(folder)
    return ready[:-2]


def capture_files(folder, run):
    files = ['physics_residency.json']
    if '--capture-replay-view' in run.get('command', []) and (folder / 'replay_view.jpg').is_file():
        files.append('replay_view.jpg')
    return files


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
            receipt = folder / 'physics.archive.json'
            run = json.loads((folder / 'run.json').read_text(encoding='utf-8'))
            record = archive(folder, capture_files(folder, run), receipt, store,
                             dict(kind='completed-physics-cadence', run_sha256=digest(folder / 'run.json')))
            result['reclaimed_bytes'] += retire(record, store, folder)
            result['manifests'].append(str(receipt))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    print(json.dumps(maintain(parser.parse_args().apply), indent=2))
