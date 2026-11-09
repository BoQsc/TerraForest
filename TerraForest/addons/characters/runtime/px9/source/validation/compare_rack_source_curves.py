#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Read-only Blender proof that Rack's non-thumb local finger keys are unchanged."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys

import bpy


BONES = {f'LeftHand{family}{joint}' for family in ('Index', 'Middle', 'Ring', 'Pinky')
         for joint in (1, 2, 3)}
CHANNEL_SIZE = {'location': 3, 'rotation_quaternion': 4, 'scale': 3}
PATH_PATTERN = re.compile(r'^pose\.bones\["([^"\\]+)"\]\.(location|rotation_quaternion|scale)$')


def sha(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def read_keys(path):
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    action = bpy.data.actions['FP_PX9_ECLIPSE_Rack']
    result = {}
    for curve in action.fcurves:
        match = PATH_PATTERN.match(curve.data_path)
        if match is None or match.group(1) not in BONES:
            continue
        bone, prop = match.groups()
        key = f'{bone}:{prop}:{curve.array_index}'
        if key in result:
            raise ValueError('Duplicate curve: ' + key)
        result[key] = {
            'bone': bone, 'property': prop, 'component': curve.array_index,
            'extrapolation': curve.extrapolation,
            'keys': [[float(point.co.x), float(point.co.y), point.interpolation]
                     for point in curve.keyframe_points],
            'modifiers': len(curve.modifiers),
        }
    expected = {f'{bone}:{prop}:{index}' for bone in BONES
                for prop, size in CHANNEL_SIZE.items() for index in range(size)}
    if set(result) != expected:
        raise ValueError('Missing/extra expected Rack non-thumb channels.')
    if any([point[0] for point in row['keys']] != list(range(73)) for row in result.values()):
        raise ValueError('Incomplete Rack source frame keys.')
    if any(point[2] != 'LINEAR' for row in result.values() for point in row['keys']):
        raise ValueError('Unexpected non-linear source interpolation.')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    baseline, candidate = args.baseline.resolve(), args.candidate.resolve()
    hashes = {name: sha(path) for name, path in [('baseline', baseline), ('candidate', candidate)]}
    old, new = read_keys(baseline), read_keys(candidate)
    changed = [name for name in sorted(old) if old[name] != new[name]]
    unchanged_files = sha(baseline) == hashes['baseline'] and sha(candidate) == hashes['candidate']
    records = []
    for bone in sorted(BONES):
        a = {name: row for name, row in old.items() if row['bone'] == bone}
        b = {name: row for name, row in new.items() if row['bone'] == bone}
        records.append({'bone': bone, 'curves': len(a),
                        'samples_per_curve': 73, 'all_local_source_keys_identical': a == b})
    report = {
        'schema': 'px9-rack-local-source-equality-1',
        'passed': not changed and unchanged_files,
        'scope': 'Exact equality of all local location, quaternion rotation and scale F-curve key coordinates, interpolation, extrapolation and modifier counts for the twelve non-thumb left finger joints in saved Rack source Actions. Read-only; files not saved.',
        'baseline_source': str(baseline), 'candidate_source': str(candidate),
        'baseline_source_sha256': hashes['baseline'], 'candidate_source_sha256': hashes['candidate'],
        'bone_count': len(BONES), 'curve_count': len(old),
        'scalar_key_count': sum(len(row['keys']) for row in old.values()),
        'all_local_source_keys_identical': not changed,
        'input_files_unmodified': unchanged_files,
        'changed_channels': changed, 'bones': records,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print('RACK_SOURCE_CURVES', json.dumps({k: v for k, v in report.items() if k != 'bones'}))
    if not report['passed']:
        raise RuntimeError('Rack local finger source keys changed; see report.')


if __name__ == '__main__':
    main()
