# SPDX-License-Identifier: 0BSD
"""Summarize a repeatable residency route, including cold-retained cadence."""
import argparse
import hashlib
import json
from statistics import median
from pathlib import Path

from analyze_frame_trace import distribution
from retained_artifacts import Store, load_manifest

ROOT = Path(__file__).resolve().parents[1]


def read_capture(folder):
    path = folder / 'physics_residency.json'
    if path.is_file():
        data = json.loads(path.read_text(encoding='utf-8'))
    else:
        record = load_manifest(folder / 'physics.archive.json')
        member = next(row for row in record['files'] if row['path'] == path.name)
        store = Store(ROOT / 'reports/retained_artifacts/chunks')
        raw = b''.join(store.get(key) for key in member['chunks'])
        if len(raw) != member['bytes'] or hashlib.sha256(raw).hexdigest() != member['sha256']:
            raise ValueError('Archived cadence failed its complete-file hash')
        data = json.loads(raw)
    receipt = folder / 'run.json'
    if receipt.is_file():
        run = json.loads(receipt.read_text(encoding='utf-8'))
        command = run.get('command', [])
        data['presentation_surface'] = ('headless' if run.get('headless') or '--headless' in command else
            'isolated_desktop' if run.get('isolated_render') or '--isolated-render' in command else
            'interactive_desktop' if '--fullscreen' in command or '--windowed' in command else 'unknown')
        if 'window_mode' not in data:
            data['window_mode'] = 0 if '--windowed' in command or '--windowed-probe' in command else 3 if '--fullscreen' in command else -1
    return data


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
    for key in ('viewport', 'physics_hz', 'vsync', 'window_mode', 'presentation_surface'):
        if key in data: result[key] = data[key]
    focus = [r['window_focused'] for r in rows if 'window_focused' in r]
    result['window_focus'] = 'unknown'
    if focus:
        result['window_focus'] = 'focused' if all(focus) else 'unfocused' if not any(focus) else 'mixed'
        result['focused_frames'] = sum(focus)
    result['diagnostics'] = data.get('diagnostics', any('render_markers' in r for r in rows))
    result['manual_no_present'] = data.get('manual_no_present', False)
    result['detached_present'] = data.get('detached_present', False)
    if 'fps_cap' in data: result['fps_cap'] = data['fps_cap']
    if 'engine_settings' in data: result['engine_settings'] = data['engine_settings']
    result['water_render_pages'] = data.get('water_render_pages', {})
    boundaries = ('physics_ms', 'physics_tail_ms', 'process_ms', 'pre_draw_ms', 'draw_ms',
                  'render_setup_ms', 'render_cpu_ms', 'gpu_ms', 'draw_calls', 'render_primitives',
                  'thread_cycles', 'draw_cycles', 'process_draw_cycles')
    result['frame_work'] = {key: distribution([r[key] for r in rows if key in r])
                            for key in boundaries if any(key in r for r in rows)}
    slow = [r for r in rows if r['frame_ms'] >= result['cadence']['frame_ms']['p99']]
    result['slow_frame_work'] = {key: distribution([r[key] for r in slow if key in r])
                                 for key in boundaries if any(key in r for r in slow)}
    result['frame_work_scope'] = ('Boundaries overlap: physics_tail and physics are within before_process. '
        'Viewport CPU/GPU timers are delayed readback, not the current draw. Detailed marker capture '
        'adds overhead; do not compare diagnostic cadence with ordinary captures.')
    groups = data.get('render_inventory', {}).get('groups', {})
    result['render_ablation'] = {}
    for phase in dict.fromkeys(r['phase'] for r in data.get('render_ablation', [])):
        subset = [r for r in data['render_ablation'] if r['phase'] == phase]
        key = phase.split(':', 1)[1]
        result['render_ablation'][phase] = dict(
            group=groups.get(key, {}).get('script', key),
            **{name: distribution([r[name] for r in subset if name in r]) for name in
               ('draw_us', 'setup_ms', 'render_cpu_ms', 'gpu_ms', 'draw_calls', 'draw_cycles')
               if any(name in r for r in subset)})
    result['corpse_ms'] = {key.removesuffix('_us'): distribution([r['corpse_us'].get(key, 0) / 1000 for r in rows])
                          for key in ('update_us', 'readiness_us', 'freeze_us', 'restore_us')}
    transitions = [r for r in data.get('ragdoll_transitions', []) if r['phase'] != 'setup']
    result['ragdolls'] = dict(available='ragdoll_transitions' in data, count=len(transitions), **{
        key.replace('_us', '_ms'): distribution([r.get(key, 0) / 1000 for r in transitions])
        for key in ('total_us', 'shape_fit_us', 'constraints_capture_us', 'max_slice_us')})
    result['ragdolls']['admission_span_ms'] = distribution([(r['end_us'] - r['begin_us']) / 1000 for r in transitions])
    bones = sorted({bone for row in transitions for bone in row.get('shapes', {})})
    result['collision_shapes'] = dict(available=bool(bones), bodies={})
    for bone in bones:
        shapes = [row['shapes'][bone] for row in transitions if bone in row.get('shapes', {})]
        result['collision_shapes']['bodies'][bone] = dict(
            count=len(shapes), plan_builds=(sum(row.get('plan_built', False) for row in shapes)
                                           if any('plan_built' in row for row in shapes) else None),
            **{key: distribution([row[key] for row in shapes if key in row]) for key in ('input_points', 'points')},
            **{key.replace('_us', '_ms'): distribution([row[key] / 1000 for row in shapes if key in row])
               for key in ('sample_us', 'cloud_us', 'resource_us', 'install_us', 'total_us')})
    events = data.get('residency_events', [])
    result['residency'] = dict(available='residency_events' in data, events=len(events),
                              deaths=sum(row['kind'] == 'died' for row in events))
    comparisons = data.get('collision_comparison', [])
    paired = {}
    for part in sorted({row['part'] for row in comparisons} | ({'all'} if comparisons else set())):
        clouds = [row for row in comparisons if part == 'all' or row['part'] == part]
        original = [median(pair['original']['total_us'] for pair in row['pairs']) / 1000 for row in clouds]
        reduced = [median(pair['reduced']['total_us'] for pair in row['pairs']) / 1000 for row in clouds]
        paired[part] = dict(clouds=len(clouds), original_ms=distribution(original), reduced_ms=distribution(reduced),
                            original_total_ms=sum(original), reduced_total_ms=sum(reduced),
                            input_points=sum(row['input_points'] for row in clouds),
                            retained_points=sum(row['pairs'][0]['reduced']['points'] for row in clouds))
    result['paired_collision'] = dict(available=bool(comparisons), parts=paired,
        scope='Post-route paired construction on identical captured posed points; median of three alternating-order fresh-resource pairs per cloud. Includes reduction cost, excludes cleanup. Not gameplay-frame timing.')
    return result


def workload_differences(first, other):
    required = ('source_sha256', 'seed', 'route')
    settings = ('viewport', 'physics_hz', 'vsync', 'fps_cap', 'diagnostics', 'manual_no_present', 'detached_present', 'engine_settings', 'presentation_surface', 'window_mode', 'window_focus')
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
