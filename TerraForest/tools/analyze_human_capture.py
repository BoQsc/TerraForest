# SPDX-License-Identifier: 0BSD
"""Summarize full human cadence separately from selective rotating spike traces."""
import argparse
import hashlib
import json
from pathlib import Path

from analyze_frame_trace import distribution


def active(row):
    return (row.get('phase') == 'human_gameplay' and row.get('window_focused', False)
            and not any(row.get(key, False) for key in ('loading', 'menu', 'inventory', 'entry')))


def summarize(observation, captures):
    samples = observation['samples']
    # A frame interval starts at the previous sample; exclude focus/menu edges.
    frames = [row for index, row in enumerate(samples) if index and active(row) and active(samples[index-1])]
    details = {row['frame']: row for capture in captures for row in capture['frames']}
    human = [row for row in samples if row.get('phase') == 'human_gameplay']
    began = human[0]['at_us'] if human else 0
    fields = ('before_process_ms', 'process_ms', 'after_process_ms', 'draw_ms', 'physics_ms',
              'physics_tail_ms', 'physics_tail_thread_cpu_ms', 'gpu_ms', 'recorder_previous_us',
              'trace_writer_active', 'physics_steps', 'zombies', 'zombie_phases_us')

    def describe(row):
        result = {key: row.get(key) for key in ('frame', 'frame_ms', 'gpu_ms', 'position', 'driving')}
        result['play_seconds'] = (row['at_us']-began)/1e6
        detail = details.get(row['frame'])
        result['detailed_trace_retained'] = detail is not None
        if detail:
            result['detail'] = {key: detail.get(key) for key in fields}
            result['largest_stages_ms'] = sorted(detail.get('stages_ms', {}).items(), key=lambda item: -item[1])[:8]
        return result

    slow = [row for row in frames if row['frame_ms'] > 100/3]
    retained = [row for row in frames if row['frame'] in details]
    seconds = {}
    for row in frames:
        seconds.setdefault(int((row['at_us']-began)/1e6), []).append(row['frame_ms'])
    clusters = []
    for row in slow:
        if not clusters or (row['at_us']-clusters[-1]['last_us']) > 1e6:
            clusters.append({'start_seconds': (row['at_us']-began)/1e6, 'last_us': row['at_us'], 'slow_frames': 0, 'max_ms': 0})
        cluster = clusters[-1]
        cluster['last_us'] = row['at_us']; cluster['slow_frames'] += 1
        cluster['max_ms'] = max(cluster['max_ms'], row['frame_ms'])
    for cluster in clusters:
        cluster['end_seconds'] = (cluster.pop('last_us')-began)/1e6
    return {
        'slot': observation['slot'], 'all_samples': len(samples), 'human_samples': len(human),
        'focused_gameplay_frames': len(frames), 'focused_gameplay_seconds': sum(row['frame_ms'] for row in frames)/1000,
        'frame_ms': distribution([row['frame_ms'] for row in frames]),
        'over_budget': {str(limit): sum(row['frame_ms'] > limit for row in frames) for limit in (100/6, 20, 100/3, 50, 100)},
        'gpu_ms': distribution([row['gpu_ms'] for row in frames]),
        'detailed_coverage_frames': len(retained), 'detailed_coverage_over_33ms': sum(row['frame'] in details for row in slow),
        'worst_frames': [describe(row) for row in sorted(frames, key=lambda row: -row['frame_ms'])[:20]],
        'worst_retained_frames': [describe(row) for row in sorted(retained, key=lambda row: -row['frame_ms'])[:20]],
        'slow_clusters': sorted(clusters, key=lambda cluster: -cluster['max_ms'])[:20],
        'per_second': [{'second': second, 'frame_ms': distribution(values)} for second, values in sorted(seconds.items())],
        'retained_triggers': [{'trigger': capture['trigger'], 'play_seconds': (capture['trigger_us']-began)/1e6,
                               'serial': capture.get('metadata', {}).get('capture_serial')} for capture in captures],
        'scope': 'Frame-post-draw cadence, not physical display presentation. Excludes loading, shutdown, focus/menu/inventory/entry frames and their edges. GPU timers may lag. Physics tail includes engine stepping, queues and synchronization; it overlaps before_process. Eight rotating traces can overwrite early spikes. Recorder overhead remains included; capped play does not establish headroom.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session', type=Path)
    args = parser.parse_args()
    files = [args.session/'observation.json', *sorted((args.session/'traces').glob('trace_*.json'))]
    data = [json.loads(path.read_text(encoding='utf-8')) for path in files]
    result = summarize(data[0], data[1:])
    result['sources'] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    output = args.session/'human_analysis.json'
    output.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('focused_gameplay_seconds', 'frame_ms', 'over_budget', 'detailed_coverage_over_33ms')}))
    print(output.resolve())


if __name__ == '__main__':
    main()
