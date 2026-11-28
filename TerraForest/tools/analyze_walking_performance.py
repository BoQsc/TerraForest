# SPDX-License-Identifier: 0BSD
"""Strict, lossless-frame walking gate. Completion is not a performance pass."""
import argparse
import hashlib
import json
import math
import struct
import zlib
from pathlib import Path

CRITICAL_MS = 1000 / 60
BUDGET_MS = 1000 / 61
HEADROOM_MS = BUDGET_MS * .8


def distribution(values):
    ordered = sorted(values)
    if not ordered:
        return None
    return {name: ordered[min(len(ordered)-1, math.ceil(q*len(ordered))-1)]
            for name, q in [('median', .5), ('p95', .95), ('p99', .99), ('max', 1)]}


def analyze(meta, rows):
    errors = list(meta.get('failures', []))
    if not rows or len(rows) != meta['frames']:
        errors.append('Missing frames')
    if meta.get('overflow'):
        errors.append('Recorder overflow')
    columns = meta['columns']
    index = {name: i for i, name in enumerate(columns)}
    if len(index) != len(columns):
        raise ValueError('Duplicate columns')
    if any(len(r) != len(columns) or not all(math.isfinite(v) for v in r) for r in rows):
        raise ValueError('Malformed or nonfinite frame')
    def values(key):
        return [r[index[key]] for r in rows]
    times = values('frame_ms')
    ids = values('frame')
    if any(b != a+1 for a, b in zip(ids, ids[1:])):
        errors.append('Nonconsecutive process frames')
    if any(t <= 0 for t in times):
        errors.append('Invalid frame interval')
    if any(values('invalid')):
        errors.append('Invalid gameplay frames retained')
    presentation = meta.get('presentation', {})
    if presentation.get('viewport') != [1920, 1080] or presentation.get('render_scale') != 1 or presentation.get('headless', True):
        errors.append('Invalid rendered resolution/scale/backend')
    expected_cap = 0 if meta['pacing'] == 'uncapped' else 61
    if any(v != expected_cap for v in values('cap')) or any(values('vsync')):
        errors.append('Pacing mode changed')
    ends = values('end_us')
    if ends and abs(sum(times)*1000-ends[-1]) > .1:
        errors.append('Cadence does not account for entire measured interval')
    if any(abs((end-(ends[n-1] if n else 0))-times[n]*1000) > .1 for n, end in enumerate(ends)):
        errors.append('Per-frame timestamps disagree with intervals')
    if sum(times) < meta['requested_seconds'] * 1000 * .98:
        errors.append('Truncated route duration')
    if meta.get('travelled_m', 0) < 40:
        errors.append('Insufficient physical movement')
    cursor = 0
    for phase in meta['phases']:
        if phase['first'] != cursor or phase['end'] < cursor:
            errors.append('Invalid phase coverage')
        if any(v != phase['id'] for v in values('phase')[phase['first']:phase['end']]):
            errors.append('Phase labels disagree')
        cursor = phase['end']
    if cursor != len(rows):
        errors.append('Unaccounted frames')
    critical = [int(r[index['frame']]) for r in rows if r[index['frame_ms']] > CRITICAL_MS]
    over61 = sum(t > BUDGET_MS for t in times)
    tail = distribution(times)
    capacity = meta['pacing'] == 'uncapped' and not meta['diagnostic']
    result = {
        'schema': 1, 'valid': not errors, 'errors': errors,
        'frames': len(rows), 'seconds': sum(times)/1000,
        'cadence_ms': tail, 'travelled_m': meta.get('travelled_m'),
        'critical_threshold_ms': CRITICAL_MS, 'critical_frames': len(critical),
        'critical_frame_ids': critical, 'over_61fps_budget': over61,
        'headroom_target_ms': HEADROOM_MS,
        'all_frames_headroom': bool(times) and all(t <= HEADROOM_MS for t in times),
        'route_61fps_pass': bool(times) and not errors and over61 == 0,
        'capacity_qualification_pass': bool(times) and not errors and capacity and all(t <= HEADROOM_MS for t in times),
        'scope': 'One engine-cadence route only. Does not establish physical display pacing, arbitrary-world coverage or universal performance.',
        'diagnostic': meta['diagnostic'], 'pacing': meta['pacing'],
        'recorder_us': distribution(values('recorder_us')),
        'phases': {}, 'diagnostics': {},
    }
    for phase in meta['phases']:
        selected = times[phase['first']:phase['end']]
        result['phases'][phase['label']] = {'frames': len(selected), 'cadence_ms': distribution(selected),
            'critical_frames': sum(t > CRITICAL_MS for t in selected)}
    if meta['diagnostic']:
        for key in columns[11:28]+columns[31:]:
            result['diagnostics'][key] = distribution([v for v in values(key) if v >= 0])
    # All slow frames remain in the binary. This small index is a convenience,
    # not a replacement for the full trace or an assumption of GPU alignment.
    result['worst_frames'] = [dict(zip(columns, row)) for row in sorted(rows, key=lambda r:r[index['frame_ms']], reverse=True)[:12]]
    return result


def read_run(folder):
    def owned_bytes(name):
        path = folder/name
        if path.is_file():
            return path.read_bytes()
        from retained_artifacts import Store, load_manifest
        manifest = load_manifest(folder/'homestead.archive.json')
        if Path(manifest['source_root']).resolve() != folder.resolve():
            raise ValueError('Cold capture ownership mismatch')
        entry = next(row for row in manifest['files'] if row['path'] == name)
        store = Store(Path(__file__).resolve().parents[1]/'reports/retained_artifacts/chunks')
        data = b''.join(store.get(key) for key in entry['chunks'])
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Cold capture byte/hash mismatch')
        return data
    meta = json.loads(owned_bytes('walking.json'))
    if meta['schema'] != 1 or not 0 <= meta['frames'] <= 24000:
        raise ValueError('Unsupported or oversized trace')
    decoder = zlib.decompressobj()
    data = decoder.decompress(owned_bytes('walking.frames.zlib'), 24000*len(meta['columns'])*8+1)
    if not decoder.eof or decoder.unused_data:
        raise ValueError('Incomplete or oversized compressed trace')
    if len(data) != meta['raw_bytes'] or hashlib.sha256(data).hexdigest() != meta['sha256']:
        raise ValueError('Trace byte/hash mismatch')
    size = len(meta['columns'])
    if len(data) != meta['frames'] * size * 8:
        raise ValueError('Trace shape mismatch')
    receipt = json.loads((folder/'run.json').read_text())
    # Reanalysis must not turn a failed engine run into a valid capture merely
    # because its timing file was flushed before the cleanup error occurred.
    if not receipt.get('result', {}).get('passed'):
        meta['failures'].append('Engine check failed')
    if not receipt.get('source_unchanged'):
        meta['failures'].append('Source changed or source consistency was not established')
    if receipt.get('jobs_after'):
        meta['failures'].append('Another render/build job active at completion')
    return meta, list(struct.iter_unpack('<'+'d'*size, data))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    args = parser.parse_args()
    result = analyze(*read_run(args.folder))
    (args.folder/'walking_analysis.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k:result[k] for k in ('valid','frames','cadence_ms','critical_frames','capacity_qualification_pass')}))
    return 0 if result['capacity_qualification_pass'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
