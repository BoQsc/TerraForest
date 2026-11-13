# SPDX-License-Identifier: 0BSD
"""Summarize controlled damage events without treating profiler stalls as gameplay."""
import argparse
import json
from pathlib import Path


def analyze(folder):
    folder = Path(folder)
    probe = json.loads((folder / 'combat_probe.json').read_text(encoding='utf-8'))
    run = json.loads((folder / 'run.json').read_text(encoding='utf-8'))
    observation = json.loads((folder / 'observation.json').read_text(encoding='utf-8'))
    frames = {(row['frame'], row['at_us']): row
              for path in (folder / 'traces').glob('trace_*.json')
              for row in json.loads(path.read_text(encoding='utf-8')).get('frames', [])}
    ordered = sorted(frames.values(), key=lambda row: row['at_us'])
    events = []
    for event in probe['events']:
        completed = event['at_us'] + event['us']
        following = next((row for row in ordered if row['at_us'] >= completed), None)
        frame = ({key: following.get(key) for key in
                  ('frame', 'frame_ms', 'process_ms', 'physics_ms', 'physics_steps', 'physics_tail_ms')}
                 if following and following['at_us'] - completed < 1000000 else None)
        events.append(dict(event, completed_frame=frame))
    phases = {}
    for sample in observation['samples']:
        phase = sample['phase']
        if phase not in ('arrival_idle', 'turning', 'settled_idle') and not phase.startswith('combat_'):
            continue
        if not sample.get('window_focused', False):
            continue
        phases.setdefault(phase, []).append(sample['frame_ms'])
    summaries = {}
    for phase, values in phases.items():
        values.sort()
        summaries[phase] = dict(frames=len(values), mean_ms=sum(values)/len(values),
                               p95_ms=values[min(len(values)-1, int(len(values)*.95))],
                               p99_ms=values[min(len(values)-1, int(len(values)*.99))],
                               max_ms=values[-1], over_60fps_budget=sum(v > 1000/60 for v in values))
    result = dict(scope='Direct damage/death lifecycle in a cloned saved world; does not replay player input.',
                  engine_profiler='--profiling' in run['command'], events=events, phases=summaries,
                  gameplay_fps_acceptance=False,
                  limitation='Short diagnostic sample, not sustained headroom qualification. Engine-profiler runs cannot establish gameplay FPS.')
    (folder / 'combat_analysis.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    args = parser.parse_args()
    result = analyze(args.folder)
    print(json.dumps(dict(engine_profiler=result['engine_profiler'],
                          event_costs_us=[dict(action=e['action'], us=e['us']) for e in result['events']],
                          phases=result['phases']), indent=2))
