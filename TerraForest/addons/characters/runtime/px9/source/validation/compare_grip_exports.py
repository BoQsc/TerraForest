#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Compare a grip-only revision with its preceding package, read-only.

Uses Python's standard library. Accessor payloads are compared semantically,
independent of their byte offsets in the GLB. This is a narrowly scoped export
regression check; it does not inspect perceived anatomy or surface contact.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


DEFAULT_ROTATION_BONES = {f'RightHand{finger}{joint}'
                          for finger in ('Middle', 'Ring', 'Pinky') for joint in (1, 2, 3)}
REVIEWABLE_EXTRA_ROTATION_BONES = {
    'RightShoulder', 'RightArm', 'RightForeArm', 'RightHand',
    'RightHandIndex1', 'RightHandIndex2', 'RightHandIndex3',
    'RightHandThumb1', 'RightHandThumb2', 'RightHandThumb3',
}
IDENTITY = [[1.0 if row == column else 0.0 for column in range(4)] for row in range(4)]
BLENDER_TO_GLTF = [[1.0, 0.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0],
                   [0.0, -1.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0]]


def sha(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


class GLB:
    FORMATS = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
    WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

    def __init__(self, path):
        data = Path(path).read_bytes()
        magic, version, size = struct.unpack_from('<4sII', data)
        assert magic == b'glTF' and version == 2 and size == len(data)
        offset = 12
        self.cache = {}
        self.records = {}
        while offset < len(data):
            length, kind = struct.unpack_from('<II', data, offset)
            offset += 8
            payload = data[offset:offset + length]
            offset += length
            if kind == 0x4e4f534a:
                self.doc = json.loads(payload)
            elif kind == 0x004e4942:
                self.binary = payload

    def raw(self, index):
        if index not in self.cache:
            accessor = self.doc['accessors'][index]
            assert not accessor.get('sparse'), 'This asset check expects dense accessors.'
            view = self.doc['bufferViews'][accessor['bufferView']]
            assert view.get('buffer', 0) == 0
            fmt = '<' + self.FORMATS[accessor['componentType']] * self.WIDTHS[accessor['type']]
            width = struct.calcsize(fmt)
            start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
            stride = view.get('byteStride', width)
            payload = b''.join(self.binary[start + row * stride:start + row * stride + width]
                               for row in range(accessor['count']))
            assert len(payload) == accessor['count'] * width
            self.cache[index] = (payload, fmt)
        return self.cache[index]

    def record(self, index):
        if index not in self.records:
            accessor = self.doc['accessors'][index]
            payload, _ = self.raw(index)
            self.records[index] = {
                key: accessor[key] for key in ('componentType', 'count', 'type')}
            self.records[index]['normalized'] = accessor.get('normalized', False)
            self.records[index]['values_sha256'] = hashlib.sha256(payload).hexdigest()
        return self.records[index]

    def values(self, index):
        payload, fmt = self.raw(index)
        return list(struct.iter_unpack(fmt, payload))

    def fixed_content(self):
        result = {key: json.loads(json.dumps(self.doc[key])) for key in
                  ('nodes', 'scenes', 'scene', 'materials', 'textures', 'samplers',
                   'extensionsUsed', 'extensionsRequired', 'skins', 'meshes', 'cameras')
                  if key in self.doc}
        for skin in result.get('skins', []):
            if 'inverseBindMatrices' in skin:
                skin['inverseBindMatrices'] = self.record(skin['inverseBindMatrices'])
        for mesh in result.get('meshes', []):
            for primitive in mesh['primitives']:
                primitive['attributes'] = {key: self.record(index)
                                           for key, index in primitive['attributes'].items()}
                if 'indices' in primitive:
                    primitive['indices'] = self.record(primitive['indices'])
                for target in primitive.get('targets', []):
                    for key in list(target):
                        target[key] = self.record(target[key])
        result['images'] = []
        for image in self.doc.get('images', []):
            row = dict(image)
            if 'bufferView' in row:
                view = self.doc['bufferViews'][row.pop('bufferView')]
                start = view.get('byteOffset', 0)
                row['payload_sha256'] = hashlib.sha256(
                    self.binary[start:start + view['byteLength']]).hexdigest()
            result['images'].append(row)
        return result

    def animations(self):
        result = {}
        for animation in self.doc.get('animations', []):
            channels = {}
            for channel in animation['channels']:
                sampler = animation['samplers'][channel['sampler']]
                node = self.doc['nodes'][channel['target']['node']]['name']
                key = (node, channel['target']['path'])
                assert key not in channels
                channels[key] = sampler
            result[animation['name']] = channels
        return result


def qangle(a, b):
    divisor = math.sqrt(sum(x * x for x in a) * sum(x * x for x in b))
    dot = min(1.0, abs(sum(x * y for x, y in zip(a, b))) / divisor)
    return math.degrees(2.0 * math.acos(dot))


def matrix_multiply(a, b):
    return [[sum(a[row][index] * b[index][column] for index in range(4))
             for column in range(4)] for row in range(4)]


def matrix_inverse(matrix):
    values = [list(map(float, row)) + IDENTITY[index][:] for index, row in enumerate(matrix)]
    for column in range(4):
        pivot = max(range(column, 4), key=lambda row: abs(values[row][column]))
        if abs(values[pivot][column]) < 1e-12:
            raise ValueError('Singular reviewed transform.')
        values[column], values[pivot] = values[pivot], values[column]
        factor = values[column][column]
        values[column] = [value / factor for value in values[column]]
        for row in range(4):
            if row == column:
                continue
            factor = values[row][column]
            values[row] = [x - factor * y for x, y in zip(values[row], values[column])]
    return [row[4:] for row in values]


def matrix_error(a, b):
    if (not isinstance(a, list) or len(a) != 4 or
            any(not isinstance(row, list) or len(row) != 4 for row in a)):
        raise ValueError('Expected a four-by-four matrix.')
    if any(not math.isfinite(value) for row in a for value in row):
        raise ValueError('Non-finite matrix component.')
    return max(abs(a[row][column] - b[row][column]) for row in range(4) for column in range(4))


def unpack_transform(value):
    result = [row[:] for row in IDENTITY]
    for column in range(3):
        for row in range(3):
            result[row][column] = value['basis_columns'][column][row]
    for row in range(3):
        result[row][3] = value['origin'][row]
    return result


def compare_reviewed_mount(baseline, candidate, reviewed, errors):
    """Check only the two generated mount representations may change."""
    station = reviewed['right_hand_in_item_blender']
    matrix_error(station, station)
    if max(abs(a - b) for a, b in zip(station[3], (0, 0, 0, 1))) > 1e-9:
        raise ValueError('Reviewed hand station must be an affine transform.')
    orthogonal_error = max(abs(sum(station[k][row] * station[k][column] for k in range(3))
                               - (1 if row == column else 0))
                           for row in range(3) for column in range(3))
    rotation = station
    determinant = (rotation[0][0] * (rotation[1][1] * rotation[2][2] - rotation[1][2] * rotation[2][1])
                   - rotation[0][1] * (rotation[1][0] * rotation[2][2] - rotation[1][2] * rotation[2][0])
                   + rotation[0][2] * (rotation[1][0] * rotation[2][1] - rotation[1][1] * rotation[2][0]))
    if orthogonal_error > 1e-6 or abs(determinant - 1) > 1e-6:
        raise ValueError('Reviewed station must be rigid, with a proper rotation.')
    rest_reference = json.loads((candidate / 'source/validation/original_r11_contract.json').read_text())
    rest_hand = rest_reference['bones']['RightHand']['matrix_local']
    convert_inverse = matrix_inverse(BLENDER_TO_GLTF)
    station_inverse = matrix_inverse(station)
    expected_local = matrix_multiply(station_inverse, convert_inverse)
    expected_rest = matrix_multiply(matrix_multiply(matrix_multiply(
        BLENDER_TO_GLTF, rest_hand), station_inverse), convert_inverse)
    definition_records = []
    for name, expected_space in (('item_px9.json', 'hand_local'),
                                 ('item_px9_rest_space.json', 'human_rest')):
        old = json.loads((baseline / name).read_text())
        new = json.loads((candidate / name).read_text())
        stripped = []
        for value in (old, new):
            row = json.loads(json.dumps(value))
            row['mount'].pop('transform')
            row['mount'].pop('rest_space_transform')
            row.pop('source_mount')
            stripped.append(row)
        unchanged = stripped[0] == stripped[1]
        if not unchanged:
            errors.append('Definition changed outside reviewed mount fields: ' + name)
        if new['mount'].get('bone') != 'RightHand' or new['mount'].get('space') != expected_space:
            errors.append('Mount bone/space contract changed: ' + name)
        source_mount = new['source_mount']
        if set(source_mount) != {'right_hand_in_item_blender', 'rest_space_matrix_godot'}:
            errors.append('Source mount schema changed: ' + name)
        local_error = matrix_error(unpack_transform(new['mount']['transform']),
                                   expected_local if expected_space == 'hand_local' else IDENTITY)
        rest_error = matrix_error(unpack_transform(new['mount']['rest_space_transform']), expected_rest)
        source_station_error = matrix_error(source_mount['right_hand_in_item_blender'], station)
        source_rest_error = matrix_error(source_mount['rest_space_matrix_godot'], expected_rest)
        if max(local_error, rest_error, source_rest_error) > 2e-6 or source_station_error > 1e-7:
            errors.append('Generated mount does not match reviewed hand station: ' + name)
        definition_records.append({
            'file': name, 'all_non_mount_fields_identical': unchanged,
            'local_transform_error': local_error, 'rest_transform_error': rest_error,
            'source_station_error': source_station_error, 'source_rest_error': source_rest_error,
        })
    canonical = GLB(candidate / 'PX9_Eclipse_FP.glb')
    wrapped = GLB(candidate / 'PX9_Eclipse_FP_RestSpace.glb')
    document = json.loads(json.dumps(wrapped.doc))
    scene = document['scenes'][document.get('scene', 0)]
    roots = scene['nodes']
    wrapper_index = len(document['nodes']) - 1
    wrapper = document['nodes'][-1]
    wrapper_valid = (roots == [wrapper_index] and wrapper.get('name') == 'PX9_Eclipse_RestSpace'
                     and set(wrapper) == {'name', 'children', 'matrix'})
    if not wrapper_valid:
        errors.append('Unexpected rest-space wrapper structure.')
    wrapper_matrix = [[wrapper['matrix'][column * 4 + row] for column in range(4)] for row in range(4)]
    wrapper_error = matrix_error(wrapper_matrix, expected_rest)
    scene['nodes'] = wrapper['children']
    document['nodes'].pop()
    wrapper_only = document == canonical.doc and wrapped.binary == canonical.binary
    if not wrapper_only or wrapper_error > 2e-6:
        errors.append('Rest-space GLB differs beyond the reviewed wrapper transform.')
    return {'reviewed_station': station, 'definitions': definition_records,
            'station_orthogonal_error': orthogonal_error, 'station_determinant': determinant,
            'rest_space_wrapper_only': wrapper_only, 'rest_space_wrapper_error': wrapper_error,
            'rest_space_glb_baseline_sha256': sha(baseline / 'PX9_Eclipse_FP_RestSpace.glb'),
            'rest_space_glb_candidate_sha256': sha(candidate / 'PX9_Eclipse_FP_RestSpace.glb')}


def compare_authored_choreography(baseline, candidate, station, errors):
    old = json.loads((baseline / 'validation/AUTHORED_FRAMES.json').read_text())
    new = json.loads((candidate / 'validation/AUTHORED_FRAMES.json').read_text())
    for field in ('fps', 'source_bone_count', 'item_bone_count', 'sample_count', 'human_rest_unchanged', 'passed'):
        if old[field] != new[field]:
            errors.append('Authored-frame contract changed: ' + field)
    if set(old['clips']) != set(new['clips']):
        errors.append('Authored-frame clip inventory changed.')
    immutable_sample_fields = ('frame', 'weapon_world_blender', 'left_hand_blender', 'left_contact',
                               'slide_offset_metres', 'magazine_delta_blender', 'case_visible')
    rows = []
    issues = []
    for action in sorted(old['clips'].keys() & new['clips'].keys()):
        a, b = old['clips'][action], new['clips'][action]
        if ({k: v for k, v in a.items() if k != 'samples'} !=
                {k: v for k, v in b.items() if k != 'samples'} or len(a['samples']) != len(b['samples'])):
            errors.append('Authored clip timing changed: ' + action)
        for previous, current in zip(a['samples'], b['samples']):
            changed = [field for field in immutable_sample_fields if previous[field] != current[field]]
            if previous['arms']['Left'] != current['arms']['Left']:
                changed.append('arms.Left')
            desired = matrix_multiply(current['weapon_world_blender'], station)
            target_error = matrix_error(current['right_hand_blender'], desired)
            if changed or target_error > 1e-5:
                issues.append({'action': action, 'frame': current['frame'],
                               'unexpected_changed_fields': changed, 'right_hand_target_error': target_error})
            rows.append({'action': action, 'frame': current['frame'],
                         'preserved_choreography_identical': not changed,
                         'right_hand_target_error': target_error})
    if issues:
        errors.append('Authored choreography or reviewed right-hand target mismatch.')
    return {'frame_samples': len(rows), 'preserved_fields': list(immutable_sample_fields) + ['arms.Left'],
            'all_preserved_samples_identical': all(row['preserved_choreography_identical'] for row in rows),
            'maximum_right_hand_target_error': max((row['right_hand_target_error'] for row in rows), default=0.0),
            'issues': issues, 'baseline_sha256': sha(baseline / 'validation/AUTHORED_FRAMES.json'),
            'candidate_sha256': sha(candidate / 'validation/AUTHORED_FRAMES.json')}


def compare(baseline, candidate, allowed_weight_vertices, reviewed=None):
    filename = 'Human.px9_eclipse.glb'
    before, after = GLB(baseline / filename), GLB(candidate / filename)
    old, new = before.animations(), after.animations()
    fixed_before, fixed_after = before.fixed_content(), after.fixed_content()
    errors = []
    allowed_rotation_bones = set(DEFAULT_ROTATION_BONES)
    roundoff_limits = {}
    if reviewed is not None:
        if reviewed.get('schema') != 'px9-grip-change-review-1':
            raise ValueError('Unknown reviewed-change schema.')
        additional = set(reviewed['additional_rotation_bones'])
        if not additional <= REVIEWABLE_EXTRA_ROTATION_BONES:
            raise ValueError('Review includes bones outside the explicit right arm/index/thumb scope.')
        allowed_rotation_bones.update(additional)
        roundoff_review = reviewed.get('nonrotation_decomposition_roundoff', {})
        if roundoff_review:
            if roundoff_review != {'translation_metres': 1e-6, 'scale_units': 2e-6,
                                  'require_both_versions_within_same_bounds_of_unchanged_rest': True}:
                raise ValueError('Only the explicitly reviewed, rest-bounded numeric tolerances are supported.')
            roundoff_limits = {'translation': 1e-6, 'scale': 2e-6}
    node_names = {node.get('name') for node in after.doc['nodes']}
    old_nodes = {node['name']: node for node in before.doc['nodes'] if 'name' in node}
    new_nodes = {node['name']: node for node in after.doc['nodes'] if 'name' in node}
    if not allowed_rotation_bones <= node_names:
        raise ValueError('A reviewed rotation bone is not present in the exported Human skeleton.')
    if old.keys() != new.keys():
        errors.append('Animation names differ.')
    fixed_differences = [key for key in fixed_before.keys() | fixed_after.keys()
                         if fixed_before.get(key) != fixed_after.get(key)]
    if fixed_differences:
        errors.append('Human GLB fixed content differs: ' + ', '.join(fixed_differences))
    changed = []
    clip_rows = []
    sample_count = 0
    for name in sorted(old.keys() & new.keys()):
        old_channels, new_channels = old[name], new[name]
        if old_channels.keys() != new_channels.keys():
            errors.append('Channel targets differ in ' + name)
        clip_changed = []
        times_unchanged = True
        for key in sorted(old_channels.keys() & new_channels.keys()):
            a, b = old_channels[key], new_channels[key]
            if (before.record(a['input']) != after.record(b['input']) or
                    a.get('interpolation', 'LINEAR') != b.get('interpolation', 'LINEAR')):
                errors.append('Timestamp/interpolation change: ' + name + ' ' + str(key))
                times_unchanged = False
            if before.record(a['output']) == after.record(b['output']):
                continue
            va, vb = before.values(a['output']), after.values(b['output'])
            allowed = key[1] == 'rotation' and key[0] in allowed_rotation_bones
            if len(va) != len(vb):
                errors.append('Sample-count change: ' + name + ' ' + str(key))
            row = {'clip': name, 'bone': key[0], 'property': key[1],
                   'within_reviewed_rotation_scope': allowed,
                   'samples': len(vb), 'changed_samples': sum(x != y for x, y in zip(va, vb)),
                   'maximum_absolute_component_difference':
                       max((abs(x - y) for ca, cb in zip(va, vb) for x, y in zip(ca, cb)), default=0.0)}
            if key[1] == 'rotation':
                row['maximum_orientation_difference_degrees'] = max(
                    (qangle(x, y) for x, y in zip(va, vb)), default=0.0)
            row['reviewed_nonrotation_roundoff'] = False
            if key[0] in allowed_rotation_bones and key[1] in roundoff_limits:
                default = [0.0, 0.0, 0.0] if key[1] == 'translation' else [1.0, 1.0, 1.0]
                rest_before = old_nodes[key[0]].get(key[1], default)
                rest_after = new_nodes[key[0]].get(key[1], default)
                old_rest_error = max((abs(value - rest) for values in va
                                      for value, rest in zip(values, rest_before)), default=0.0)
                new_rest_error = max((abs(value - rest) for values in vb
                                      for value, rest in zip(values, rest_after)), default=0.0)
                limit = roundoff_limits[key[1]]
                numeric_ok = (rest_before == rest_after and
                              max(row['maximum_absolute_component_difference'], old_rest_error, new_rest_error) <= limit)
                row.update({'reviewed_nonrotation_roundoff': numeric_ok, 'roundoff_limit': limit,
                            'baseline_maximum_rest_deviation': old_rest_error,
                            'candidate_maximum_rest_deviation': new_rest_error})
                allowed = allowed or numeric_ok
            row['change_class'] = ('reviewed_rotation' if row['within_reviewed_rotation_scope'] else
                                   'rest_bounded_decomposition_roundoff' if row['reviewed_nonrotation_roundoff'] else
                                   'unexpected')
            changed.append(row)
            clip_changed.append(key[0] + ':' + key[1])
            if not allowed:
                errors.append('Unexpected changed channel: ' + name + ' ' + str(key))
        first = next(iter(new_channels.values()))
        frames = after.record(first['input'])['count']
        sample_count += frames
        clip_rows.append({'clip': name, 'frames': frames,
                          'timestamps_and_interpolation_identical': times_unchanged,
                          'changed_channels': clip_changed})

    preserve = {
        'Human.r11.glb', 'PX9_Eclipse_FP.glb', 'PX9_Eclipse_FP_RestSpace.glb',
        'item_px9.json', 'item_px9_rest_space.json', 'project.godot',
        'LICENSE.txt', 'THIRD_PARTY_NOTICES.txt', 'TEXTURE_PROVENANCE.json',
        'source/human_hand_weights.py', 'source/human_arm_solver.py',
        'source/author_px9_first_person.py', 'validation/AUTHORED_FRAMES.json',
    }
    preserve.update(path.name for path in baseline.glob('*.gd'))
    mount_review, choreography_review = None, None
    reviewed_source_revisions = []
    if reviewed is not None:
        preserve.difference_update({'item_px9.json', 'item_px9_rest_space.json',
                                    'PX9_Eclipse_FP_RestSpace.glb', 'validation/AUTHORED_FRAMES.json'})
        mount_review = compare_reviewed_mount(baseline, candidate, reviewed, errors)
        choreography_review = compare_authored_choreography(
            baseline, candidate, reviewed['right_hand_in_item_blender'], errors)
        author_revision = reviewed.get('author_definition_sync')
        if author_revision is not None:
            name = 'source/author_px9_first_person.py'
            actual_old, actual_new = sha(baseline / name), sha(candidate / name)
            if (author_revision.get('baseline_sha256') != actual_old or
                    author_revision.get('candidate_sha256') != actual_new):
                errors.append('Author definition-sync source revision differs from its exact reviewed hashes.')
            else:
                preserve.remove(name)
            reviewed_source_revisions.append({'file': name, 'baseline_sha256': actual_old,
                                              'candidate_sha256': actual_new,
                                              'review_reason': 'Only import copy and synchronized generation of the alternate rest-space item definition.'})
    file_rows = []
    for relative in sorted(preserve):
        a, b = baseline / relative, candidate / relative
        if not a.is_file() or not b.is_file():
            errors.append('Missing preservation input: ' + relative)
            continue
        old_hash, new_hash = sha(a), sha(b)
        identical = old_hash == new_hash
        file_rows.append({'file': relative, 'baseline_sha256': old_hash,
                          'candidate_sha256': new_hash, 'identical': identical})
        if not identical:
            errors.append('Preservation input changed: ' + relative)
    patches = []
    for package in (baseline, candidate):
        runtime_patch = package / 'Human.px9_eclipse.hand_weights.json'
        source_patch = package / 'source/hand_weight_patch.json'
        if sha(runtime_patch) != sha(source_patch):
            errors.append('Source/runtime patch mismatch in ' + str(package))
        patches.append(json.loads(source_patch.read_text()))
    old_rows = {row['vertex']: row for row in patches[0]['vertices']}
    new_rows = {row['vertex']: row for row in patches[1]['vertices']}
    weight_rows = []
    for vertex in sorted(old_rows.keys() | new_rows.keys()):
        a, b = old_rows.get(vertex), new_rows.get(vertex)
        if a == b:
            continue
        if vertex not in allowed_weight_vertices:
            errors.append('Unexpected changed hand-weight row: ' + str(vertex))
        if a is None or b is None:
            errors.append('Patch source-row inventory differs at vertex ' + str(vertex))
            weight_rows.append({'vertex': vertex, 'baseline': a, 'candidate': b})
            continue
        changed_fields = sorted(key for key in a.keys() | b.keys() if a.get(key) != b.get(key))
        for key in ('position_blender', 'position_gltf', 'old_weights', 'side'):
            if a.get(key) != b.get(key):
                errors.append('Source identity changed in patch row ' + str(vertex) + ': ' + key)
        weight_rows.append({'vertex': vertex, 'changed_fields': changed_fields,
                            'baseline_weights': a['weights'], 'candidate_weights': b['weights'],
                            'baseline_finger': a.get('finger'), 'candidate_finger': b.get('finger')})
    variant_before = sha(baseline / 'Human.px9_eclipse.body.res')
    variant_after = sha(candidate / 'Human.px9_eclipse.body.res')
    if not weight_rows and variant_before != variant_after:
        errors.append('Native body resource changed without any authorized patch-row change.')
    if weight_rows and variant_before == variant_after:
        errors.append('Native body resource has not been regenerated for the reviewed patch changes.')
    native_import = json.loads((candidate / 'ANIMATION_IMPORT_REPORT.json').read_text())
    native_skin = native_import.get('hand_skin_variant', {})
    native_checks = {
        'native_import_passed': native_import.get('passed') is True,
        'native_animation_source_hash_current': native_import.get('animation_source_sha256') == sha(candidate / filename),
        'native_definition_hash_current': native_import.get('definition_sha256') == sha(candidate / 'item_px9.json'),
        'native_animation_library_hash_current': native_import.get('output_sha256') == sha(candidate / 'Human.px9_eclipse.res'),
        'native_skin_patch_hash_current': native_skin.get('source_patch_sha256') == sha(candidate / 'source/hand_weight_patch.json'),
        'native_body_hash_current': native_skin.get('output_sha256') == variant_after,
        'native_skin_variant_passed': native_skin.get('passed') is True,
        'native_geometry_and_morph_buffers_preserved': native_skin.get('raw_geometry_and_morph_buffers_byte_identical') is True,
        'native_saved_geometry_buffers_preserved': native_skin.get('saved_geometry_buffers_byte_identical') is True,
        'native_saved_skin_buffers_match': native_skin.get('saved_skin_buffers_match_variant') is True,
        'native_nonhand_weights_preserved': native_skin.get('original_native_non_hand_weights_preserved') is True,
        'native_unpatched_skin_records_preserved': native_skin.get('unpatched_skin_records_byte_identical') is True,
    }
    if not all(native_checks.values()):
        errors.append('Native import freshness/buffer check failed: ' + ', '.join(
            name for name, passed in native_checks.items() if not passed))
    if not changed:
        errors.append('No finger animation output changed.')
    return {
        'schema': 'px9-grip-only-export-regression-1',
        'passed': not errors, 'errors': errors,
        'baseline': str(baseline), 'candidate': str(candidate),
        'baseline_human_glb_sha256': sha(baseline / filename),
        'candidate_human_glb_sha256': sha(candidate / filename),
        'scope': 'Byte identity for designated preserved inputs; semantic Human animation GLB mesh/rest/bind identity; exact timestamp and interpolation identity; meaningful output changes limited to explicitly reviewed right-arm and right-finger rotations. Only if explicitly reviewed, those same bones may carry tightly bounded translation/scale decomposition noise while both versions remain within the same bounds of unchanged rest values. Hand-patch row changes are confined to an explicit reviewed vertex allowlist. Reviewed hand stations, generated mount representations, unchanged weapon/left-hand choreography, and native import hash freshness are checked independently. This does not validate skin collisions or visual anatomy.',
        'fixed_content_differences': fixed_differences,
        'paired_clip_count': len(clip_rows), 'inclusive_frame_samples': sample_count,
        'preserved_files': file_rows, 'clips': clip_rows,
        'changed_channels': changed,
        'allowed_rotation_bones': sorted(allowed_rotation_bones),
        'actual_changed_rotation_bones': sorted({row['bone'] for row in changed if row['property'] == 'rotation'}),
        'all_left_side_channels_byte_identical': not any(row['bone'].startswith('Left') for row in changed),
        'all_nonrotation_channels_byte_identical': all(row['property'] == 'rotation' for row in changed),
        'all_nonrotation_changes_are_reviewed_rest_bounded_roundoff': all(
            row['reviewed_nonrotation_roundoff'] for row in changed if row['property'] != 'rotation'),
        'nonrotation_roundoff_summary': {
            path: {'limit': roundoff_limits.get(path),
                   'changed_channel_count': sum(row['property'] == path for row in changed),
                   'maximum_component_delta': max((row['maximum_absolute_component_difference']
                       for row in changed if row['property'] == path), default=0.0),
                   'maximum_baseline_rest_deviation': max((row.get('baseline_maximum_rest_deviation', 0.0)
                       for row in changed if row['property'] == path), default=0.0),
                   'maximum_candidate_rest_deviation': max((row.get('candidate_maximum_rest_deviation', 0.0)
                       for row in changed if row['property'] == path), default=0.0)}
            for path in ('translation', 'scale')},
        'reviewed_source_revisions': reviewed_source_revisions,
        'reviewed_mount': mount_review, 'authored_choreography': choreography_review,
        'native_import_checks': native_checks,
        'hand_patch': {
            'baseline_sha256': sha(baseline / 'source/hand_weight_patch.json'),
            'candidate_sha256': sha(candidate / 'source/hand_weight_patch.json'),
            'allowed_changed_vertex_rows': sorted(allowed_weight_vertices),
            'changed_rows': weight_rows,
            'native_body_baseline_sha256': variant_before,
            'native_body_candidate_sha256': variant_after,
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--allow-weight-vertices', default='',
                        help='Comma-separated reviewed source vertex IDs whose patch rows may change.')
    parser.add_argument('--review', type=Path,
                        help='Explicit reviewed hand station and additional right-arm/index/thumb rotation bones.')
    args = parser.parse_args()
    allowed = {int(value) for value in args.allow_weight_vertices.split(',') if value}
    reviewed = json.loads(args.review.read_text()) if args.review else None
    report = compare(args.baseline.resolve(), args.candidate.resolve(), allowed, reviewed)
    report['review_file'] = {'path': str(args.review.resolve()), 'sha256': sha(args.review)} if args.review else None
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({
        'passed': report['passed'], 'report': str(args.report), 'error_count': len(report['errors']),
        'first_errors': report['errors'][:20], 'clip_count': report['paired_clip_count'],
        'frame_samples': report['inclusive_frame_samples'],
        'actual_changed_rotation_bones': report['actual_changed_rotation_bones'],
        'all_left_side_channels_byte_identical': report['all_left_side_channels_byte_identical'],
        'all_nonrotation_changes_are_reviewed_rest_bounded_roundoff': report['all_nonrotation_changes_are_reviewed_rest_bounded_roundoff'],
        'nonrotation_roundoff_summary': report['nonrotation_roundoff_summary'],
        'native_import_checks': report['native_import_checks'],
    }, indent=2))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
