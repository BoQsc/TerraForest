# SPDX-License-Identifier: 0BSD
"""Summarize a repeatable residency route, including cold-retained cadence."""
import argparse
import hashlib
import json
from pathlib import Path

from analyze_frame_trace import distribution
from retained_artifacts import Store, load_manifest

ROOT = Path(__file__).resolve().parents[1]


def read_capture(folder):
    path = folder / 'physics_residency.json'
    if path.is_file():
        return json.loads(path.read_text(encoding='utf-8'))
    record = load_manifest(folder / 'physics.archive.json')
    member = next(row for row in record['files'] if row['path'] == path.name)
    store = Store(ROOT / 'reports/retained_artifacts/chunks')
    data = b''.join(store.get(key) for key in member['chunks'])
    if len(data) != member['bytes'] or hashlib.sha256(data).hexdigest() != member['sha256']:
        raise ValueError('Archived cadence failed its complete-file hash')
    return json.loads(data)


def summarize(data):
    rows = data['samples']
    def cadence(samples):
        return dict(frames=len(samples), frame_ms=distribution([r['frame_ms'] for r in samples]),
                    over_33_ms=sum(r['frame_ms'] > 1000 / 30 for r in samples),
                    over_50_ms=sum(r['frame_ms'] > 50 for r in samples),
                    physics_tail_ms=distribution([r['physics_tail_ms'] for r in samples]))
    result = dict(source=data['source'], source_sha256=data['source_sha256'], seed=data['seed'],
                  scope=data['scope'], route=data['route'], cadence=cadence(rows),
                  phases={phase: cadence([r for r in rows if r['phase'] == phase])
                          for phase in dict.fromkeys(r['phase'] for r in rows)})
    for key in ('viewport', 'physics_hz', 'vsync'):
        if key in data: result[key] = data[key]
    result['corpse_ms'] = {key.removesuffix('_us'): distribution([r['corpse_us'].get(key, 0) / 1000 for r in rows])
                          for key in ('update_us', 'readiness_us', 'freeze_us', 'restore_us')}
    transitions = [r for r in data.get('ragdoll_transitions', []) if r['phase'] != 'setup']
    result['ragdolls'] = dict(available='ragdoll_transitions' in data, count=len(transitions), **{
        key.replace('_us', '_ms'): distribution([r.get(key, 0) / 1000 for r in transitions])
        for key in ('total_us', 'shape_fit_us', 'constraints_capture_us', 'max_slice_us')})
    result['ragdolls']['admission_span_ms'] = distribution([(r['end_us'] - r['begin_us']) / 1000 for r in transitions])
    events = data.get('residency_events', [])
    result['residency'] = dict(available='residency_events' in data, events=len(events),
                              deaths=sum(row['kind'] == 'died' for row in events))
    return result


def workload_differences(first, other):
    required = ('source_sha256', 'seed', 'route')
    settings = ('viewport', 'physics_hz', 'vsync')
    return [key for key in required if first[key] != other[key]] + [
        key for key in settings if key in first and key in other and first[key] != other[key]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs', nargs='+', type=Path)
    args = parser.parse_args()
    summaries = []
    for folder in args.runs:
        result = summarize(read_capture(folder))
        (folder / 'physics_summary.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        summaries.append(result)
        print(json.dumps(dict(run=str(folder), cadence=result['cadence'], corpse_ms=result['corpse_ms'], ragdolls=result['ragdolls'])))
    if len(summaries) > 1:
        first = summaries[0]
        for other in summaries[1:]:
            differences = workload_differences(first, other)
            if differences:
                raise SystemExit('Workload differs (' + ', '.join(differences) + '): inspect state, endpoints, populations and settings before comparing timing.')
        print('MATCH source hash, seed, route endpoints and end-of-leg populations. This is not a deterministic full-world state check; verify input/settings provenance in run.json.')
        missing = [key for key in ('viewport', 'physics_hz', 'vsync') if any(key not in item for item in summaries)]
        if missing: print('Earlier capture lacks explicit settings: ' + ', '.join(missing))


if __name__ == '__main__':
    main()
