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


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    result = maintain_traces(apply=args.apply)
    print(json.dumps(result, indent=2))
