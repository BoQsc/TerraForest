# SPDX-License-Identifier: CC0-1.0
"""Sample paired GLBs independently at every authored frame using mathutils.

Run in Blender factory startup; no scene or asset is imported or modified.
This checks rigid hand/part anchor relationships, not skin interpenetration.
"""
from pathlib import Path
import argparse
import bisect
import hashlib
import json
import math
import sys
from mathutils import Matrix, Quaternion, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from validate_first_person_exports import Glb

parser = argparse.ArgumentParser()
parser.add_argument('--definition', type=Path, required=True)
parser.add_argument('--frames', type=Path, required=True)
parser.add_argument('--human', type=Path, required=True)
parser.add_argument('--weapon', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])


def unpack_matrix(columns):
    return Matrix([[columns[column * 4 + row] for column in range(4)] for row in range(4)])


def trs(node):
    if 'matrix' in node:
        return unpack_matrix(node['matrix']).decompose()
    t = Vector(node.get('translation', [0, 0, 0]))
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    return t, Quaternion((w, x, y, z)), Vector(node.get('scale', [1, 1, 1]))


def frame_sample(times, values, moment, rotation=False):
    end = bisect.bisect_left(times, moment)
    if end >= len(times):
        return values[-1]
    if end == 0 or abs(times[end] - moment) <= 1e-6:
        return values[end]
    start = end - 1
    if abs(times[start] - moment) <= 1e-6:
        return values[start]
    t = (moment - times[start]) / (times[end] - times[start])
    if rotation:
        a = Quaternion((values[start][3], *values[start][:3]))
        b = Quaternion((values[end][3], *values[end][:3]))
        q = a.slerp(b, t)
        return q.x, q.y, q.z, q.w
    return tuple(a + (b - a) * t for a, b in zip(values[start], values[end]))


class PoseReader:
    def __init__(self, path, allowed_clips):
        self.glb = Glb(path)
        self.nodes = self.glb.doc['nodes']
        self.defaults = [trs(node) for node in self.nodes]
        self.parents = {}
        self.names = {node.get('name', str(index)): index for index, node in enumerate(self.nodes)}
        for index, node in enumerate(self.nodes):
            for child in node.get('children', []):
                self.parents[child] = index
        self.clips = {}
        for animation in self.glb.doc['animations']:
            if animation['name'] not in allowed_clips:
                continue
            channels = []
            for channel in animation['channels']:
                sampler = animation['samplers'][channel['sampler']]
                if sampler.get('interpolation', 'LINEAR') != 'LINEAR':
                    raise ValueError('Contact sampler expects linearly baked animation')
                target = channel['target']
                if target.get('path') not in ('translation', 'rotation', 'scale'):
                    raise ValueError('Contact sampler expects bone TRS only')
                channels.append((target['node'], target['path'],
                                 [x[0] for x in self.glb.accessor(sampler['input'])],
                                 self.glb.accessor(sampler['output'])))
            self.clips[animation['name']] = channels

    def pose(self, name, frame):
        local_trs = [list(row) for row in self.defaults]
        time = frame / 60.0
        for node, path, times, values in self.clips[name]:
            value = frame_sample(times, values, time, path == 'rotation')
            if path == 'translation':
                local_trs[node][0] = Vector(value)
            elif path == 'rotation':
                local_trs[node][1] = Quaternion((value[3], *value[:3]))
            else:
                local_trs[node][2] = Vector(value)
        local = [Matrix.LocRotScale(*row) for row in local_trs]
        world = {}
        def visit(index):
            if index in world:
                return world[index]
            world[index] = visit(self.parents[index]) @ local[index] if index in self.parents else local[index]
            return world[index]
        for index in range(len(self.nodes)):
            visit(index)
        return {name: world[index] for name, index in self.names.items()}


def error(a, b):
    translation = (a.translation - b.translation).length
    qa = a.to_quaternion().normalized()
    qb = b.to_quaternion().normalized()
    # Normalize the dot in Python double precision. mathutils' float32 dot
    # can turn sub-microradian agreement into a spurious ~0.00069rad angle.
    norm = math.sqrt(sum(float(value) * float(value) for value in qa)
                     * sum(float(value) * float(value) for value in qb))
    dot = max(-1.0, min(1.0, abs(sum(float(x) * float(y) for x, y in zip(qa, qb))) / norm))
    radians = 2.0 * math.acos(dot)
    basis = max((a.to_3x3().col[index] - b.to_3x3().col[index]).length for index in range(3))
    return {'translation_metres': translation, 'basis_axis_error': basis, 'rotation_radians': radians}


def packed_matrix(value):
    columns, origin = value['basis_columns'], value['origin']
    return Matrix([[columns[column][row] for column in range(3)] + [origin[row]] for row in range(3)]
                  + [[0, 0, 0, 1]])


definition = json.loads(args.definition.read_text())
authored = json.loads(args.frames.read_text())
human = PoseReader(args.human, {row['human_clip'] for row in definition['actions']})
weapon = PoseReader(args.weapon, {row['item_clip'] for row in definition['actions']})
mount = packed_matrix(definition['mount']['transform'])
convert = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
convert_inverse = convert.inverted()
anchors = {}
anchor_origins = {}
contact_stats = {}
clip_records = []
return_records = []
errors = []
total = 0
maximum_mount = {'translation_metres': 0.0, 'basis_axis_error': 0.0, 'rotation_radians': 0.0}
max_mount_sample = None
rows_by_id = {row['id']: row for row in definition['actions']}

for row in definition['actions']:
    clip_frames = authored['clips'][row['id']]['samples']
    if [sample['frame'] for sample in clip_frames] != list(range(row['frame_end'] + 1)):
        errors.append({'clip': row['id'], 'issue': 'incomplete_authoring_frame_reference'})
    clip_max_mount = {key: 0.0 for key in maximum_mount}
    contact_counts = {}
    for sample in clip_frames:
        frame = sample['frame']
        total += 1
        h = human.pose(row['human_clip'], frame)
        w = weapon.pose(row['item_clip'], frame)
        item_world = h['RightHand'] @ mount
        intended = convert @ Matrix(sample['weapon_world_blender']) @ convert_inverse
        difference = error(item_world, intended)
        for key, value in difference.items():
            clip_max_mount[key] = max(clip_max_mount[key], value)
            if value > maximum_mount[key]:
                maximum_mount[key] = value
                max_mount_sample = {'clip': row['id'], 'frame': frame, 'metric': key, 'value': value}
        if difference['translation_metres'] > 0.00002 or difference['basis_axis_error'] > 0.00002:
            errors.append({'clip': row['id'], 'frame': frame, 'issue': 'exported_right_hand_mount_disagrees_with_authoring', 'difference': difference})
        contact = sample.get('left_contact')
        if contact not in ('support', 'magazine', 'slide'):
            continue
        part_world = item_world if contact == 'support' else item_world @ w[contact]
        relative = part_world.inverted() @ h['LeftHand']
        contact_counts[contact] = contact_counts.get(contact, 0) + 1
        if contact not in anchors:
            anchors[contact] = relative.copy()
            anchor_origins[contact] = {'clip': row['id'], 'frame': frame, 'matrix': [list(r) for r in relative]}
            contact_stats[contact] = {'frames': 0, 'maximum_translation_metres': 0.0,
                                      'maximum_basis_axis_error': 0.0, 'maximum_rotation_radians': 0.0}
        difference = error(relative, anchors[contact])
        stats = contact_stats[contact]
        stats['frames'] += 1
        stats['maximum_translation_metres'] = max(stats['maximum_translation_metres'], difference['translation_metres'])
        stats['maximum_basis_axis_error'] = max(stats['maximum_basis_axis_error'], difference['basis_axis_error'])
        stats['maximum_rotation_radians'] = max(stats['maximum_rotation_radians'], difference['rotation_radians'])
        if difference['translation_metres'] > 0.0001 or difference['basis_axis_error'] > 0.0001:
            errors.append({'clip': row['id'], 'frame': frame, 'issue': 'declared_left_contact_drift',
                           'contact': contact, 'difference': difference})
    clip_records.append({'id': row['id'], 'sample_count': len(clip_frames),
                         'maximum_mount_error': clip_max_mount, 'left_contact_frame_counts': contact_counts})
    if row.get('return_action'):
        target = rows_by_id[row['return_action']]
        h_end = human.pose(row['human_clip'], row['frame_end'])
        h_start = human.pose(target['human_clip'], 0)
        w_end = weapon.pose(row['item_clip'], row['frame_end'])
        w_start = weapon.pose(target['item_clip'], 0)
        hand_differences = {hand: error(h_end[hand], h_start[hand]) for hand in ('RightHand', 'LeftHand')}
        mechanical_differences = {}
        for name in ['weapon_root', 'frame', 'slide', 'barrel', 'muzzle_housing', 'guide_rod', 'magazine',
                     'magazine_base', 'trigger', 'grip_panel_left', 'grip_panel_right', 'takedown',
                     'slide_stop', 'magazine_release', 'frame_pins', 'front_sight', 'rear_sight', 'ejected_case']:
            difference = error(w_end[name], w_start[name])
            if difference['translation_metres'] > 0.00002 or difference['basis_axis_error'] > 0.00002:
                mechanical_differences[name] = difference
        if mechanical_differences:
            errors.append({'clip': row['id'], 'target': row['return_action'],
                           'issue': 'mechanical_return_endpoint_mismatch', 'bones': mechanical_differences})
        return_records.append({'source': row['id'], 'target': row['return_action'],
                               'hand_differences': hand_differences,
                               'mechanical_endpoints_match': not mechanical_differences,
                               'mechanical_differences': mechanical_differences,
                               'human_hands_require_transition_blend': any(d['translation_metres'] > 0.0001 or d['basis_axis_error'] > 0.0001 for d in hand_differences.values())})

expected_count = sum(row['frame_end'] + 1 for row in definition['actions'])
if total != expected_count or authored['sample_count'] != expected_count:
    errors.append({'issue': 'wrong_sample_count', 'actual': total, 'expected': expected_count})
report = {
    'schema': 'px9-exported-frame-contacts-1', 'passed': not errors,
    'errors': errors, 'fps': 60, 'sample_count': total,
    'inputs': {label: {'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
               for label, path in [('definition', args.definition), ('authored_frames', args.frames),
                                   ('human_glb', args.human), ('weapon_glb', args.weapon)]},
    'maximum_exported_mount_error': maximum_mount, 'maximum_mount_sample': max_mount_sample,
    'left_contact_stats': contact_stats, 'left_contact_anchor_frames': anchor_origins,
    'clips': clip_records, 'return_endpoint_comparisons': return_records,
    'tolerances': {'mount_translation_metres': 0.00002, 'mount_basis_axis_error': 0.00002,
                   'left_contact_translation_metres': 0.0001, 'left_contact_basis_axis_error': 0.0001,
                   'mechanical_endpoint_translation_metres': 0.00002, 'mechanical_endpoint_basis_axis_error': 0.00002},
    'scope': 'Independent sampling of raw GLB joint channels at every authored integer frame. Checks exported right-hand attachment against authored weapon matrices and stability of declared left-hand support/magazine/slide anchors. Records human return-pose differences for runtime blending and asserts item mechanical endpoint continuity. Does not prove skin collision avoidance or perceived anatomical quality; native-engine playback and rendering are checked separately.',
}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('EXPORTED_CONTACTS', json.dumps({'passed': report['passed'], 'samples': total,
      'errors': len(errors), 'maximum_mount_error': maximum_mount,
      'left_contacts': contact_stats,
      'human_returns_needing_blend': [row['source'] for row in return_records if row['human_hands_require_transition_blend']],
      'report': str(args.report)}))
if errors:
    raise RuntimeError('Exported contact or endpoint contract failed; see report')
