# SPDX-License-Identifier: 0BSD
"""Cold-retain completed rolling traces; keep two ordinary captures ready."""
import json
from pathlib import Path

from development_storage import admit
from maintain_performance_artifacts import ROOT, no_game_processes, owned_lease
from retained_artifacts import Store, archive, confined, digest, retire, ordinary_ancestors


def candidates(root=ROOT, keep=2):
    root = Path(root).resolve()
    ready = []
    for manifest in sorted((root/'reports/performance_changes').glob('*/run.json')):
        folder = confined(manifest.parent, root/'reports/performance_changes')
        if not (folder/'completion.json').is_file() or (folder/'traces.archive.json').exists():
            continue
        run = json.loads(manifest.read_text(encoding='utf-8'))
        if run.get('result', {}).get('exit_code') is None:
            continue
        command = run.get('command', [])
        if not any('frame_trace_world.gd' in str(arg) for arg in command):
            continue
        traces = folder/'traces'
        declared = [str(arg).split('=', 1)[1] for arg in command if str(arg).startswith('--frame-trace-dir=')]
        if len(declared) != 1 or Path(declared[0]).resolve() != traces.resolve():
            continue
        if not traces.is_dir() or not list(traces.glob('trace_*.json')):
            continue
        # A completion for a different world is not ownership of this capture.
        completion = json.loads((folder/'completion.json').read_text(encoding='utf-8'))
        if '--trace-world-slot='+str(completion.get('slot', '')) not in command:
            continue
        ready.append(folder)
    ordinary = [p for p in ready if not (p/'.retain').exists() and not (p/'RETAIN_READY').exists()]
    return ordinary[:-keep] if keep else ordinary


def maintain_traces(root=ROOT, apply=False):
    root = Path(root).resolve()
    selected = candidates(root)
    result = {'candidates': [str(p) for p in selected], 'completed': [], 'reclaimed_bytes': 0, 'archive_bytes_added': 0}
    if not apply or not selected:
        return result
    # Only small receipts are added to loose reports. Chunk store separately
    # enforces its approved archive budget and verifies full reconstruction.
    admit(root, report_bytes=1024*1024, world_bytes=0)
    no_game_processes()
    ordinary_ancestors(root/'reports/retained_artifacts')
    (root/'reports/retained_artifacts').mkdir(parents=True, exist_ok=True)
    with owned_lease(root/'reports/retained_artifacts/writer', root):
        store = Store(root/'reports/retained_artifacts/chunks')
        before = store.bytes
        for folder in selected:
            if result['reclaimed_bytes'] >= 512*1024*1024:
                break
            files = sorted((folder/'traces').glob('trace_*.json'))
            record = archive(folder, ['traces/'+p.name for p in files], folder/'traces.archive.json', store,
                             {'kind': 'completed-rolling-traces', 'run_sha256': digest(folder/'run.json'),
                              'completion_sha256': digest(folder/'completion.json')})
            result['reclaimed_bytes'] += retire(record, store, folder)
            result['completed'].append(str(folder/'traces.archive.json'))
        result['archive_bytes_added'] = store.bytes-before
    return result


def maintain_observations(root=ROOT, apply=False):
    """Retain full cadence and unreferenced captures after the owned driver exits."""
    root = Path(root).resolve()
    ready = []
    for manifest in sorted((root/'reports/performance_changes').glob('*/run.json')):
        folder = confined(manifest.parent, root/'reports/performance_changes')
        if not (folder/'observation.json').is_file() or (folder/'observation.archive.json').exists():
            continue
        run = json.loads(manifest.read_text(encoding='utf-8'))
        observation = json.loads((folder/'observation.json').read_text(encoding='utf-8'))
        completion = json.loads((folder/'completion.json').read_text(encoding='utf-8')) if (folder/'completion.json').exists() else observation
        command = run.get('command', [])
        if (run.get('result', {}).get('exit_code') is None or
                not any(Path(str(arg)).name == 'frame_trace_world.gd' for arg in command) or
                '--trace-world-slot='+str(completion.get('slot', '')) not in command or
                completion.get('slot') != observation.get('slot') or
                '--trace-world-output='+folder.as_posix() not in command):
            continue
        if not (folder/'.retain').exists() and not (folder/'RETAIN_READY').exists():
            ready.append(folder)
    selected = ready[:-2]
    result = {'candidates': [str(p) for p in selected], 'completed': [], 'reclaimed_bytes': 0}
    if not apply or not selected:
        return result
    admit(root, report_bytes=1024*1024, world_bytes=0)
    no_game_processes()
    ordinary_ancestors(root/'reports/retained_artifacts')
    (root/'reports/retained_artifacts').mkdir(parents=True, exist_ok=True)
    with owned_lease(root/'reports/retained_artifacts/writer', root):
        from retire_backed_outputs import referenced_media
        referenced = referenced_media(root)
        store = Store(root/'reports/retained_artifacts/chunks')
        for folder in selected:
            names = ['arrival.png', 'destruction_before.png', 'destruction_after.png', 'destruction_settled.png',
                     'outdoor_0.png', 'outdoor_1.png']
            members = ['observation.json'] + [name for name in names if (folder/name).is_file() and
                'project/'+(folder/name).relative_to(root).as_posix() not in referenced]
            record = archive(folder, members, folder/'observation.archive.json', store,
                             {'kind': 'completed-frame-cadence', 'run_sha256': digest(folder/'run.json'),
                              'completion_sha256': digest(folder/'completion.json') if (folder/'completion.json').exists() else None})
            result['reclaimed_bytes'] += retire(record, store, folder)
            result['completed'].append(str(folder/'observation.archive.json'))
    return result


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    result = maintain_traces(apply=args.apply)
    print(json.dumps(result, indent=2))
