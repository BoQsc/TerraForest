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
NAMES.update(name.replace(".png", ".webp") for name in tuple(NAMES) if name.startswith(("player_shore_", "player_lake_")))
NAMES.update(("authoring_brush_0.png","authoring_brush_1.png"))
NAMES.update(("world_editor_terrain.png","world_editor_water.png"))


NAMES.update(f"cut_{phase}_angle_{angle}.png" for phase in ("before","after") for angle in (1,2))


def candidates(root=ROOT, keep_ready=2, families=None):
    if keep_ready not in (1, 2):
        raise ValueError('Keep one or two ready runs; archived evidence remains restorable')
    ready = {'water_barrel_world': [], 'water_player_world': [], 'authoring_brush': [], 'authoring_cut_angles': [], 'world_editor': []}
    for manifest in sorted((root / 'reports/checks').glob('*/run.json')):
        run = json.loads(manifest.read_text(encoding='utf-8'))
        if run.get('result', {}).get('exit_code') is None:
            continue
        command = run.get('command', [])
        if '--script' in command:
            script = command[command.index('--script') + 1]
        elif '--water-qualification-driver=res://qualification/water_player_world.gd' in command:
            script = str(manifest.parent / 'water_player_world.gd')
        else:
            continue
        family = Path(script).stem
        if family not in ready:
            continue
        if script not in ('res://tests/' + family + '.gd', str(root / 'tests' / (family + '.gd'))):
            driver = manifest.parent / (family + '.gd')
            packaged = '--main-pack' in command
            receipt = Path(run.get('release_receipt', ''))
            if receipt.name == 'candidate.json' and receipt.parent.parent == root / 'reports/checks' and receipt.is_file():
                candidate = json.loads(receipt.read_text(encoding='utf-8'))
                folder_name = str(manifest.parent)
                closed = candidate.get('released') is True or (
                    folder_name in candidate.get('closed_runs', {}) and
                    candidate['closed_runs'][folder_name] == digest(manifest))
                packaged |= (closed and folder_name in candidate.get('runs', {}).values()
                             and candidate.get('pack_sha256') == run.get('pack_sha256')
                             and candidate.get('driver_sha256') == run.get('driver_sha256'))
            driver_hash = run.get('driver_sha256')
            if not driver_hash and '--main-pack' in command and run.get('test_sha256'):
                # The earlier packaged contact driver recorded the same source
                # hash under test_sha256, alongside its frozen terrain overlay.
                overlay = manifest.parent / 'terrain_contact.zip'
                if overlay.is_file() and run.get('patch_sha256') == digest(overlay):
                    driver_hash = run['test_sha256']
            if (not packaged or script != str(driver) or not driver.is_file()
                    or not run.get('pack_sha256') or driver_hash != digest(driver)):
                continue
        if family == 'water_player_world' and '--authoring-captures' in command and '--water-load-only' in command:
            family = 'authoring_brush'
        if family == 'water_player_world' and '--authoring-cut-angles' in command and '--water-load-only' in command:
            family = 'authoring_cut_angles'
        if family == 'water_player_world' and '--editor-review' in command:
            family = 'world_editor'
        if families is not None and family not in families:
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


def maintain(apply=False, root=ROOT, keep_ready=2, families=None):
    selected = candidates(root, keep_ready, families)
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
