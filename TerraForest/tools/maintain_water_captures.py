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
    'deposition_underwater', 'object_contact_above', 'object_contact_underwater')}
NAMES.update(('post_blast.water', 'post_terrain.water'))
NAMES.update(name + '.png' for name in ('player_shore_before', 'player_shore_after', 'player_shore_underwater', 'player_lake_before', 'player_lake_after', 'player_lake_underwater'))
REVERSE_NAMES = {name + '_reverse.png' for name in ('player_shore_before', 'player_shore_after', 'player_lake_before', 'player_lake_after')}
NAMES.update(REVERSE_NAMES)


def candidates(root=ROOT, keep_ready=2):
    if keep_ready not in (1, 2):
        raise ValueError('Keep one or two ready runs; archived evidence remains restorable')
    ready = {'water_barrel_world': [], 'water_player_world': []}
    for manifest in sorted((root / 'reports/checks').glob('*/run.json')):
        run = json.loads(manifest.read_text(encoding='utf-8'))
        if run.get('result', {}).get('exit_code') is None:
            continue
        command = run.get('command', [])
        if '--script' not in command:
            continue
        script = command[command.index('--script') + 1]
        family = Path(script).stem
        if family not in ready or script not in ('res://tests/' + family + '.gd', str(root / 'tests' / (family + '.gd'))):
            continue
        folder = confined(manifest.parent, root / 'reports/checks')
        if '--check-evidence-dir=' + str(folder) not in command:
            continue
        if (folder / 'captures.archive.json').exists() and (
                (folder / 'captures.supplement.archive.json').exists() or
                not any((folder / name).is_file() for name in REVERSE_NAMES)):
            continue
        if any((folder / pin).exists() for pin in ('.retain', 'RETAIN_READY')):
            continue
        if any((folder / name).is_file() for name in NAMES):
            ready[family].append(folder)
    return [folder for family in ready.values() for folder in family[:-keep_ready]]


def maintain(apply=False, root=ROOT, keep_ready=2):
    selected = candidates(root, keep_ready)
    result = dict(keep_ready=keep_ready, candidates=[str(p) for p in selected], reclaimed_bytes=0, manifests=[])
    if not apply or not selected:
        return result
    admit(root, report_bytes=1024 * 1024, world_bytes=0)
    no_game_processes()
    with owned_lease(root / 'reports/retained_artifacts/writer', root):
        store = Store(root / 'reports/retained_artifacts/chunks')
        for folder in selected:
            no_game_processes()
            members = sorted(name for name in NAMES if (folder / name).is_file())
            receipt = 'captures.supplement.archive.json' if (folder / 'captures.archive.json').exists() else 'captures.archive.json'
            record = archive(folder, members, folder / receipt, store,
                             dict(kind='completed-water-captures', run_sha256=digest(folder / 'run.json')))
            result['reclaimed_bytes'] += retire(record, store, folder)
            result['manifests'].append(str(folder / receipt))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--keep-ready', type=int, choices=(1, 2), default=2)
    args = parser.parse_args()
    print(json.dumps(maintain(args.apply, keep_ready=args.keep_ready), indent=2))
