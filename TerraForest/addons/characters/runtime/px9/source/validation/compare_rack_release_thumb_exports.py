#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Strict, read-only Rack revision 8 exported-change contract (stdlib only).

Inputs are complete baseline and candidate package directories. Intended changes
are Rack release rotations on the three left-thumb joints, frames041..057.
Additional named left-finger chains can be allowed explicitly after review.
The held grasp through040, arm/wrist channels, every other human channel,
all other clips, weapon GLBs, mesh/rest/
bind data, optional skin patch/body, item definitions and event times remain exact. Tiny rest-bounded Rack
translation/scale decomposition noise is explicitly classified, never silently
treated as intentional movement. This gate does not assess anatomy or contact.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

RACK = 'FP_PX9_ECLIPSE_Rack'
ALLOWED = {'LeftHandThumb' + str(joint) for joint in (1, 2, 3)}
NOISE = {'translation': 1e-6, 'scale': 2e-6}
PROTECTED = (
    'PX9_Eclipse_FP.glb', 'PX9_Eclipse_FP_RestSpace.glb', 'Human.r11.glb',
    'item_px9.json', 'item_px9_rest_space.json', 'LICENSE.txt',
    'TEXTURE_PROVENANCE.json',
    'Human.px9_eclipse.body.res', 'Human.px9_eclipse.hand_weights.json',
    'source/hand_weight_patch.json', 'source/human_hand_weights.py',
    'source/human_hand_skin_revision.py', 'source/human_arm_solver.py',
)


def sha(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


class GLB:
    FORMATS = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
    WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4,
              'MAT2': 4, 'MAT3': 9, 'MAT4': 16}

    def __init__(self, path):
        self.path = Path(path)
        data = self.path.read_bytes()
        if len(data) < 12 or struct.unpack_from('<4sII', data) != (b'glTF', 2, len(data)):
            raise ValueError(f'Invalid GLB header: {path}')
        self.doc, self.binary, self.cache = None, None, {}
        offset = 12
        while offset < len(data):
            size, kind = struct.unpack_from('<II', data, offset)
            offset += 8
            payload = data[offset:offset + size]
            offset += size
            if len(payload) != size:
                raise ValueError('Truncated chunk')
            if kind == 0x4e4f534a:
                if self.doc is not None:
                    raise ValueError('Multiple JSON chunks')
                self.doc = json.loads(payload)
            elif kind == 0x004e4942:
                if self.binary is not None:
                    raise ValueError('Multiple binary chunks')
                self.binary = payload
        if offset != len(data) or self.doc is None or self.binary is None:
            raise ValueError('Missing or malformed GLB chunks')
        names = [n.get('name') for n in self.doc['nodes']]
        if None in names or len(names) != len(set(names)):
            raise ValueError('This contract requires unique named nodes')
        self.nodes = {n['name']: n for n in self.doc['nodes']}

    def accessor(self, index):
        if index not in self.cache:
            acc = self.doc['accessors'][index]
            if acc.get('sparse'):
                raise ValueError('Sparse accessor not expected')
            view = self.doc['bufferViews'][acc['bufferView']]
            if view.get('buffer', 0) != 0:
                raise ValueError('External buffer not expected')
            fmt = '<' + self.FORMATS[acc['componentType']] * self.WIDTHS[acc['type']]
            width = struct.calcsize(fmt)
            start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
            stride = view.get('byteStride', width)
            if stride < width:
                raise ValueError('Invalid stride')
            payload = b''.join(self.binary[start + i * stride:start + i * stride + width]
                               for i in range(acc['count']))
            if len(payload) != acc['count'] * width:
                raise ValueError('Truncated accessor')
            record = {k: acc[k] for k in ('componentType', 'count', 'type')}
            record['normalized'] = acc.get('normalized', False)
            record['values_sha256'] = hashlib.sha256(payload).hexdigest()
            self.cache[index] = (record, list(struct.iter_unpack(fmt, payload)))
        return self.cache[index]

    def fixed_content(self):
        excluded = {'animations', 'accessors', 'bufferViews', 'buffers'}
        fixed = {k: json.loads(json.dumps(v)) for k, v in self.doc.items() if k not in excluded}
        for skin in fixed.get('skins', []):
            if 'inverseBindMatrices' in skin:
                skin['inverseBindMatrices'] = self.accessor(skin['inverseBindMatrices'])[0]
        for mesh in fixed.get('meshes', []):
            for prim in mesh['primitives']:
                prim['attributes'] = {k: self.accessor(i)[0] for k, i in prim['attributes'].items()}
                if 'indices' in prim:
                    prim['indices'] = self.accessor(prim['indices'])[0]
                for morph in prim.get('targets', []):
                    for k in morph:
                        morph[k] = self.accessor(morph[k])[0]
        for image in fixed.get('images', []):
            if 'bufferView' in image:
                view = self.doc['bufferViews'][image.pop('bufferView')]
                at = view.get('byteOffset', 0)
                image['payload_sha256'] = hashlib.sha256(
                    self.binary[at:at + view['byteLength']]).hexdigest()
        return fixed

    def animations(self):
        result = {}
        for animation in self.doc.get('animations', []):
            name = animation['name']
            if name in result:
                raise ValueError('Duplicate clip: ' + name)
            channels = {}
            for channel in animation['channels']:
                target = channel['target']
                key = (self.doc['nodes'][target['node']]['name'], target['path'])
                if key in channels:
                    raise ValueError('Duplicate channel: ' + str(key))
                channels[key] = animation['samplers'][channel['sampler']]
            result[name] = {
                'metadata': {k: v for k, v in animation.items() if k not in ('channels', 'samplers')},
                'channels': channels,
            }
        return result


def qangle(a, b):
    na, nb = math.hypot(*a), math.hypot(*b)
    if na < 1e-12 or nb < 1e-12:
        raise ValueError('Degenerate quaternion')
    a, b = tuple(v / na for v in a), tuple(v / nb for v in b)
    if math.fsum(x * y for x, y in zip(a, b)) < 0:
        b = tuple(-v for v in b)
    return math.degrees(4 * math.atan2(math.dist(a, b), math.hypot(*(x + y for x, y in zip(a, b)))))


def compare(baseline, candidate, start, end, identity_check=False):
    errors, changes, clips, frame_rows = [], [], [], {f: [] for f in range(73)}
    before = GLB(baseline / 'Human.px9_eclipse.glb')
    after = GLB(candidate / 'Human.px9_eclipse.glb')
    fixed_a, fixed_b = before.fixed_content(), after.fixed_content()
    fixed_differences = sorted(k for k in fixed_a.keys() | fixed_b.keys() if fixed_a.get(k) != fixed_b.get(k))
    if fixed_differences:
        errors.append('Human fixed mesh/rest/bind content changed: ' + ', '.join(fixed_differences))
    aa, ab = before.animations(), after.animations()
    if aa.keys() != ab.keys() or len(aa) != 20 or RACK not in ab:
        errors.append('Expected identical inventory of 20 human clips including Rack')
    if not ALLOWED <= after.nodes.keys():
        errors.append('Missing required left-arm/finger nodes')
    total_samples = 0
    for name in sorted(aa.keys() & ab.keys()):
        ca, cb = aa[name], ab[name]
        if ca['metadata'] != cb['metadata'] or ca['channels'].keys() != cb['channels'].keys():
            errors.append('Clip metadata/channel inventory changed: ' + name)
        changed_clip = []
        clip_times = None
        for key in sorted(ca['channels'].keys() & cb['channels'].keys()):
            sa, sb = ca['channels'][key], cb['channels'][key]
            ia, ta = before.accessor(sa['input'])
            ib, tb = after.accessor(sb['input'])
            meta_a = {k: v for k, v in sa.items() if k not in ('input', 'output')}
            meta_b = {k: v for k, v in sb.items() if k not in ('input', 'output')}
            if ia != ib or meta_a != meta_b or sb.get('interpolation', 'LINEAR') != 'LINEAR':
                errors.append('Time/interpolation changed: ' + name + ' ' + str(key))
            if clip_times is None:
                clip_times = tb
            elif clip_times != tb:
                errors.append('Nonuniform full-frame sampling: ' + name + ' ' + str(key))
            oa, va = before.accessor(sa['output'])
            ob, vb = after.accessor(sb['output'])
            if {k: v for k, v in oa.items() if k != 'values_sha256'} != {
                    k: v for k, v in ob.items() if k != 'values_sha256'}:
                errors.append('Output accessor format/count changed: ' + name + ' ' + str(key))
            if len(va) != len(vb) or len(vb) != len(tb):
                errors.append('Key count changed: ' + name + ' ' + str(key))
                continue
            if any(not math.isfinite(x) for v in vb for x in v):
                errors.append('Nonfinite output: ' + name + ' ' + str(key))
                continue
            if key[1] == 'rotation' and any(len(v) != 4 or abs(math.hypot(*v) - 1) > 2e-6 for v in vb):
                errors.append('Invalid unit quaternion output: ' + name + ' ' + str(key))
            if any(not math.isfinite(t[0]) or abs(t[0] * 60 - i) > 1e-4 for i, t in enumerate(tb)):
                errors.append('Expected inclusive 60 FPS sampling: ' + name + ' ' + str(key))
            if oa == ob:
                continue
            indices = [i for i, (a, b) in enumerate(zip(va, vb)) if a != b]
            frames = [round(tb[i][0] * 60) for i in indices]
            scope = name == RACK and key[0] in ALLOWED and bool(frames) and all(start <= f <= end for f in frames)
            delta = max((abs(x-y) for a, b in zip(va, vb) for x, y in zip(a, b)), default=0)
            allowed, classification = scope and key[1] == 'rotation', 'unexpected'
            row = {'clip': name, 'bone': key[0], 'property': key[1],
                   'changed_frames': frames, 'changed_times_seconds': [tb[i][0] for i in indices],
                   'changed_key_count': len(indices), 'maximum_component_difference': delta}
            if allowed:
                classification = 'intentional_rack_left_rotation'
                row['maximum_orientation_difference_degrees'] = max(qangle(a, b) for a, b in zip(va, vb))
            elif scope and key[1] in NOISE:
                default = [0., 0., 0.] if key[1] == 'translation' else [1., 1., 1.]
                rest_a = before.nodes[key[0]].get(key[1], default)
                rest_b = after.nodes[key[0]].get(key[1], default)
                dev_a = max(abs(x-r) for v in va for x, r in zip(v, rest_a))
                dev_b = max(abs(x-r) for v in vb for x, r in zip(v, rest_b))
                allowed = rest_a == rest_b and max(delta, dev_a, dev_b) <= NOISE[key[1]]
                row.update({'roundoff_limit': NOISE[key[1]],
                            'baseline_maximum_rest_deviation': dev_a,
                            'candidate_maximum_rest_deviation': dev_b})
                if allowed:
                    classification = 'rest_bounded_decomposition_roundoff'
            row.update({'allowed': allowed, 'classification': classification})
            changes.append(row)
            changed_clip.append(key[0] + ':' + key[1])
            if name == RACK:
                for i, frame in zip(indices, frames):
                    value_delta = max(abs(x-y) for x, y in zip(va[i], vb[i]))
                    item = {'bone': key[0], 'property': key[1], 'component_difference': value_delta,
                            'allowed': allowed, 'classification': classification}
                    if key[1] == 'rotation':
                        item['orientation_difference_degrees'] = qangle(va[i], vb[i])
                    frame_rows.setdefault(frame, []).append(item)
            if not allowed:
                errors.append('Forbidden output change: ' + name + ' ' + str(key))
        total_samples += len(clip_times or [])
        clips.append({'name': name, 'samples': len(clip_times or []),
                      'unchanged_output_bytes': not changed_clip, 'changed_channels': changed_clip})
    if total_samples != 1582:
        errors.append('Expected 1,582 inclusive authored human samples')
    if not identity_check and not any(c['classification'] == 'intentional_rack_left_rotation' for c in changes):
        errors.append('No intentional Rack pose change found')
    files = []
    for relative in PROTECTED:
        a, b = baseline / relative, candidate / relative
        if not a.is_file() or not b.is_file():
            errors.append('Missing protected file: ' + relative)
            continue
        ha, hb = sha(a), sha(b)
        files.append({'path': relative, 'baseline_sha256': ha, 'candidate_sha256': hb, 'identical': ha == hb})
        if ha != hb:
            errors.append('Protected weapon/definition/reference/license/skin/solver changed: ' + relative)
    changed_frames = [f for row in changes for f in row['changed_frames']]
    thumb44_changed = any(row['bone'].startswith('LeftHandThumb') and row['property'] == 'rotation' and 44 in row['changed_frames'] for row in changes)
    if not identity_check and not thumb44_changed:
        errors.append('Requested Rack044 thumb pose has no exported rotation change.')
    return {
        'schema': 'px9-rack-release-thumb-revision8-regression-1', 'passed': not errors, 'errors': errors,
        'scope': __doc__.strip(), 'baseline': str(baseline), 'candidate': str(candidate),
        'baseline_human_sha256': sha(before.path), 'candidate_human_sha256': sha(after.path),
        'allowed_rotation_bones': sorted(ALLOWED), 'allowed_frame_window': [start, end],
        'roundoff_limits': NOISE, 'human_fixed_content_identical': not fixed_differences,
        'human_fixed_content_differences': fixed_differences, 'clip_count': len(clips),
        'inclusive_sample_count': total_samples, 'clips': clips, 'changed_channels': changes,
        'changed_frame_range': [min(changed_frames, default=None), max(changed_frames, default=None)],
        'all_non_rack_outputs_byte_identical': not any(c['clip'] != RACK for c in changes),
        'all_non_allowed_bones_byte_identical': not any(c['bone'] not in ALLOWED for c in changes),
        'all_right_outputs_byte_identical': not any(c['bone'].startswith('Right') for c in changes),
        'rack_boundary_samples_byte_identical': not any(f < start or f > end for f in changed_frames),
        'rack_frame044_thumb_changed': thumb44_changed,
        'rack_frame031_byte_identical': 31 not in changed_frames,
        'rack_frames000_through040_byte_identical': not any(f <= 40 for f in changed_frames),
        'rack_frames058_through072_byte_identical': not any(f >= 58 for f in changed_frames),
        'all_arm_wrist_outputs_byte_identical': not any(c['bone'] in {'LeftShoulder','LeftArm','LeftForeArm','LeftHand','RightShoulder','RightArm','RightForeArm','RightHand'} for c in changes),
        'protected_files': files,
        'rack_per_frame': [{'frame': f, 'seconds': f / 60, 'changes': rows} for f, rows in sorted(frame_rows.items())],
        'limitations': ['No skin-clearance or anatomy assessment.',
                        'No Blender original-Action or native-import freshness assessment.',
                        'The accepted revision5 optional skin patch and native body are required byte-identical; this revision is animation-only.'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--frame-start', type=int, default=41)
    parser.add_argument('--frame-end', type=int, default=57)
    parser.add_argument('--identity-check', action='store_true')
    parser.add_argument('--allow-finger', action='append', default=[], choices=('Index','Middle','Ring','Pinky'),
                        help='Explicitly reviewed additional left-finger chain; default allows only Thumb.')
    args = parser.parse_args()
    if (args.frame_start, args.frame_end) != (41, 57):
        parser.error('Revision8 edit window is fixed to Rack041..057.')
    ALLOWED.update('LeftHand'+finger+str(joint) for finger in args.allow_finger for joint in (1,2,3))
    report = compare(args.baseline.resolve(), args.candidate.resolve(), args.frame_start,
                     args.frame_end, args.identity_check)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    summary_keys = ('passed', 'errors', 'clip_count', 'inclusive_sample_count',
                    'changed_frame_range', 'all_non_rack_outputs_byte_identical',
                    'all_non_allowed_bones_byte_identical', 'all_right_outputs_byte_identical',
                    'rack_boundary_samples_byte_identical', 'human_fixed_content_identical',
                    'rack_frame031_byte_identical', 'rack_frames000_through040_byte_identical',
                    'rack_frames058_through072_byte_identical', 'all_arm_wrist_outputs_byte_identical')
    print(json.dumps({**{k: report[k] for k in summary_keys},
                      'changed_rotation_bones': sorted({c['bone'] for c in report['changed_channels']
                                                        if c['classification'] == 'intentional_rack_left_rotation'}),
                      'report': str(args.report)}, indent=2))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
