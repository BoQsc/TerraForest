"""Summarize one rolling-trace session without counting overlapping frames twice."""
# SPDX-License-Identifier: 0BSD
import argparse
from bisect import bisect_left
import hashlib
import json
from pathlib import Path


def distribution(values):
    values = sorted(values)
    n = len(values)
    if not n:
        return None
    return {"samples": n, "mean": sum(values) / n, "p50": values[n // 2],
            "p95": values[min(n - 1, int(n * .95))],
            "p99": values[min(n - 1, int(n * .99))],
            "p999": values[min(n - 1, int(n * .999))], "maximum": values[-1]}


def destruction_events(rows):
    events = {}
    for row in rows:
        for transition in row.get('destruction', {}).get('transitions', []):
            event = events.setdefault(transition['event'], {'phases': {}, 'trigger_tick': transition['trigger_tick'],
                                                           'deadline_tick': transition['deadline_tick']})
            event['phases'][transition['phase']] = transition
    return {'events': events,
            'observed_deadline_misses': sum('deadline_missed' in event['phases'] for event in events.values()),
            'maximum_pending': max((row.get('destruction', {}).get('pending', 0) for row in rows), default=0),
            'maximum_dropped': max((row.get('destruction', {}).get('dropped', 0) for row in rows), default=0),
            'scope': 'Observed event transitions only; missing phases are unknown. Store/terrain completion does not certify building-render/physics publication.'}


def render_marker_gaps(rows):
    # Device frame numbers need not identify the callback that reports them.
    # Match absolute CPU stamps only when the full gap lies inside a known draw.
    ends = [row['at_us'] for row in rows]
    seen, gaps = set(), []
    missing = truncated = 0
    for reporter in rows:
        markers = reporter.get('render_markers', {})
        if not markers.get('available') or markers.get('repeated'):
            continue
        identity = (markers.get('device_frame'), markers.get('begin_cpu_us'), markers.get('end_cpu_us'))
        if identity in seen:
            continue
        seen.add(identity)
        truncated += bool(markers.get('truncated'))
        for gap in markers.get('largest_cpu_gaps', []):
            begin, elapsed = gap['begin_cpu_us'], gap['cpu_us']
            index = bisect_left(ends, begin + elapsed)
            match = rows[index] if index < len(rows) else None
            if elapsed < 0 or match is None or 'draw_ms' not in match or begin < match['at_us'] - match['draw_ms'] * 1000:
                missing += 1
                continue
            gaps.append(dict(gap, frame=match['frame'], phase=match['phase'], frame_ms=match['frame_ms'],
                             reported_in_frame=reporter['frame'], device_frame=markers.get('device_frame')))
    return {'completed_frames': len(seen), 'truncated_frames': truncated, 'unmatched_gaps': missing,
            'largest_cpu_gaps': sorted(gaps, key=lambda gap: -gap['cpu_us'])[:50],
            'scope': 'Adjacent CPU marker gaps matched by absolute timestamps inside retained draw intervals. Delayed device frames are not current gameplay frames. Partial top-gap sample, not inclusive scopes or a complete CPU sum.'}


def native_process_profiles(rows):
    owners = sorted({owner for row in rows for owner in row.get('native_world_process', {})})
    result = {}
    for owner in owners:
        samples = [row.get('native_world_process', {}).get(owner, {}) for row in rows]
        available = [sample for sample in samples if sample.get('available', False)]
        current = [sample for sample in available if sample.get('current', False)]
        keys = sorted({key for sample in current for key in sample
                       if key.endswith('_us') and key not in ('started_us', 'ended_us')})
        result[owner] = {'current_samples': len(current), 'stale_samples': len(available) - len(current),
                         'unavailable_samples': len(samples) - len(available),
                         'timings_us': {key: distribution(sample[key] for sample in current if key in sample) for key in keys}}
    return result


def summarize(captures):
    frames = {}
    for capture in captures:
        if capture.get("schema") != 1:
            raise ValueError("Unsupported trace schema")
        for row in capture["frames"]:
            identity = (row["frame"], row["at_us"])
            if identity in frames and frames[identity] != row:
                raise ValueError("Overlapping captures disagree about an immutable frame")
            frames[identity] = row
    rows = sorted(frames.values(), key=lambda r: r["at_us"])
    lookup = {r["frame"]: r for r in rows}
    phases = {}
    for phase in dict.fromkeys(r["phase"] for r in rows):
        selected = [r for r in rows if r["phase"] == phase]
        metrics = {key: distribution([r[key] for r in selected if key in r]) for key in
                   ("frame_ms", "process_ms", "draw_ms", "before_process_ms", "after_process_ms",
                    "physics_ms", "gpu_ms", "render_cpu_ms", "render_setup_cpu_ms", "recorder_previous_us", "draw_calls", "primitives")}
        metrics["over_20ms_frames"] = sum(r["frame_ms"] > 20 for r in selected)
        metrics["native_world_process"] = native_process_profiles(selected)
        tails = [r for r in selected if r.get('physics_tail_complete', False)]
        metrics['physics_tail'] = {
            'complete_frames': len(tails), 'unavailable_or_incomplete_frames': len(selected) - len(tails),
            'wall_ms': distribution(r['physics_tail_ms'] for r in tails),
            'thread_cpu_ms': distribution(r['physics_tail_thread_cpu_ms'] for r in tails if 'physics_tail_thread_cpu_ms' in r),
            'scope': 'After late physics callbacks through the next physics/process signal. Engine stepping, queues, synchronization and other work overlap before_process_ms; not isolated Jolt time.'}
        phases[phase] = metrics
    worst = []
    for row in sorted(rows, key=lambda r: r["frame_ms"], reverse=True)[:20]:
        prior = lookup.get(row["frame"] - 1)
        record = dict(row)
        record["pipeline_deltas"] = {
            key: row[key] - prior[key] if prior is not None else None
            for key in ("pipeline_draw", "pipeline_specialization") if key in row}
        # Stages are nested. Preserve them; never add their maxima together.
        record["stages_ms"] = dict(sorted(row.get("stages_ms", {}).items(), key=lambda x: -x[1]))
        worst.append(record)
    return {"unique_frames": len(rows), "phases": phases, "slowest_frames": worst,
            "destruction": destruction_events(rows),
            "render_markers": render_marker_gaps(rows),
            "scope": "Triggered windows only, not an unbiased whole-session distribution. Overlapping frames deduplicated. Stages/physics overlap wall intervals. GPU timers may lag. Missing adjacent frames give unknown compilation deltas."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path, help="One session directory or one trace JSON")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    files = sorted(args.session.glob("trace_*.json")) if args.session.is_dir() else [args.session]
    if not files:
        parser.error("No trace files found")
    captures = [json.loads(path.read_text(encoding="utf-8")) for path in files]
    result = summarize(captures)
    result["sources"] = [{"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                          "trigger": data["trigger"], "metadata": data["metadata"], "truncated": data["truncated"]}
                         for path, data in zip(files, captures)]
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    for phase, metrics in result["phases"].items():
        value = metrics["frame_ms"]
        print(f"{phase}: n={value['samples']} p99={value['p99']:.3f} ms max={value['maximum']:.3f} ms")
    print(f"{result['unique_frames']} unique frames in {len(files)} triggered windows")
    if args.output:
        print(args.output.resolve())


if __name__ == "__main__":
    main()
