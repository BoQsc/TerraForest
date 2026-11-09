#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Read-only regression gate for a localized PX-9 Rack left-hand pose edit.

Only Python's standard library is used. GLB accessors are compared independently
of binary layout. All other clips, the right hand/body, weapon, rest/bind/mesh,
skin patch, native skin resource, material textures, license and timing stay
identical. Explicitly named Rack left-hand/arm rotations are the sole animation
edit scope. Optional translation/scale tolerance is limited to those same Rack
bones and to tiny decomposition noise about the identical rest transform.
An explicit, separate roundoff-only list can cover the twelve non-thumb finger
joints when a hash-bound Blender source comparison proves all their local keys
remain identical. That list never permits an intentional finger rotation edit.

This checks the exported change boundary and native-import freshness. It does
not prove skin clearance, visual anatomy, or preservation of original Blender
Actions; those require the complementary source/contact/visual checks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


RACK_CLIP = 'FP_PX9_ECLIPSE_Rack'
FINGER_BONES = {f'LeftHand{finger}{joint}'
                for finger in ('Index', 'Middle', 'Ring', 'Pinky', 'Thumb')
                for joint in (1, 2, 3)}
ARM_BONES = {'LeftShoulder', 'LeftArm', 'LeftForeArm', 'LeftHand'}
ALLOWED_BONES = FINGER_BONES | ARM_BONES
NONTHUMB_FINGER_BONES = {bone for bone in FINGER_BONES if 'Thumb' not in bone}
ROUND_OFF_LIMITS = {'translation': 1e-6, 'scale': 2e-6}
ROTATION_ROUNDOFF_DEGREES = 0.00003
QUATERNION_COMPONENT_ROUNDOFF = 3e-7


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def load(path):
    return json.loads(Path(path).read_text())


class GLB:
    FORMATS = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
    WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4,
              'MAT2': 4, 'MAT3': 9, 'MAT4': 16}

    def __init__(self, path):
        self.path = Path(path)
        data = self.path.read_bytes()
        magic, version, size = struct.unpack_from('<4sII', data)
        if (magic, version, size) != (b'glTF', 2, len(data)):
            raise ValueError('Invalid GLB header: ' + str(path))
        self.doc = None
        self.binary = b''
        self.cache = {}
        self.records = {}
        offset = 12
        while offset < len(data):
            length, kind = struct.unpack_from('<II', data, offset)
            offset += 8
            payload = data[offset:offset + length]
            if len(payload) != length:
                raise ValueError('Truncated GLB chunk.')
            offset += length
            if kind == 0x4e4f534a:
                if self.doc is not None:
                    raise ValueError('Multiple JSON chunks.')
                self.doc = json.loads(payload)
            elif kind == 0x004e4942:
                if self.binary:
                    raise ValueError('Multiple binary chunks.')
                self.binary = payload
        if offset != len(data) or self.doc is None:
            raise ValueError('Invalid GLB payload.')
        names = [node.get('name') for node in self.doc['nodes']]
        if any(name is None for name in names) or len(set(names)) != len(names):
            raise ValueError('This contract requires unique, named GLB nodes.')

    def raw(self, index):
        if index not in self.cache:
            accessor = self.doc['accessors'][index]
            if accessor.get('sparse'):
                raise ValueError('Dense accessors are required for this asset.')
            view = self.doc['bufferViews'][accessor['bufferView']]
            if view.get('buffer', 0) != 0:
                raise ValueError('Expected the embedded GLB buffer.')
            fmt = '<' + self.FORMATS[accessor['componentType']] * self.WIDTHS[accessor['type']]
            width = struct.calcsize(fmt)
            start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
            stride = view.get('byteStride', width)
            payload = b''.join(self.binary[start + row * stride:start + row * stride + width]
                               for row in range(accessor['count']))
            if len(payload) != accessor['count'] * width:
                raise ValueError('Truncated accessor.')
            self.cache[index] = (payload, fmt)
        return self.cache[index]

    def record(self, index):
        if index not in self.records:
            accessor = self.doc['accessors'][index]
            payload, _ = self.raw(index)
            result = {key: accessor[key] for key in ('componentType', 'count', 'type')}
            result['normalized'] = accessor.get('normalized', False)
            result['values_sha256'] = hashlib.sha256(payload).hexdigest()
            self.records[index] = result
        return self.records[index]

    def values(self, index):
        payload, fmt = self.raw(index)
        return list(struct.iter_unpack(fmt, payload))

    def fixed_content(self):
        excluded = {'animations', 'accessors', 'bufferViews', 'buffers'}
        result = {key: json.loads(json.dumps(value))
                  for key, value in self.doc.items() if key not in excluded}
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
        for row in result.get('images', []):
            if 'bufferView' in row:
                view = self.doc['bufferViews'][row.pop('bufferView')]
                start = view.get('byteOffset', 0)
                row['payload_sha256'] = hashlib.sha256(
                    self.binary[start:start + view['byteLength']]).hexdigest()
        return result

    def animations(self):
        result = {}
        for animation in self.doc.get('animations', []):
            name = animation['name']
            if name in result:
                raise ValueError('Duplicate animation name: ' + name)
            channels = {}
            for channel in animation['channels']:
                sampler = animation['samplers'][channel['sampler']]
                target = channel['target']
                node = self.doc['nodes'][target['node']]['name']
                key = (node, target['path'])
                if key in channels:
                    raise ValueError('Duplicate animation target: ' + str(key))
                channels[key] = sampler
            metadata = {key: value for key, value in animation.items()
                        if key not in ('channels', 'samplers')}
            result[name] = {'channels': channels, 'metadata': metadata}
        return result


def qangle(a, b):
    norm_a, norm_b = math.hypot(*a), math.hypot(*b)
    if not norm_a or not norm_b:
        return float('inf')
    a, b = tuple(value / norm_a for value in a), tuple(value / norm_b for value in b)
    if math.fsum(x * y for x, y in zip(a, b)) < 0:
        b = tuple(-value for value in b)
    # The normalized quaternion chord formula avoids acos cancellation near
    # identical rotations. Values are evaluated in Python double precision.
    return math.degrees(4.0 * math.atan2(math.dist(a, b), math.hypot(*(x + y for x, y in zip(a, b)))))


def within_window(frame, window):
    return window[0] <= frame <= window[1]


def compare_animations(before, after, bones, window, allow_roundoff, errors,
                       roundoff_bones=frozenset(), rotation_roundoff_limit=ROTATION_ROUNDOFF_DEGREES):
    old, new = before.animations(), after.animations()
    if old.keys() != new.keys():
        errors.append('Human animation inventory changed.')
    if RACK_CLIP not in old or RACK_CLIP not in new:
        errors.append('Expected Rack animation is missing.')
    old_nodes = {node['name']: node for node in before.doc['nodes']}
    new_nodes = {node['name']: node for node in after.doc['nodes']}
    if not bones <= set(new_nodes):
        errors.append('An allowed rotation bone is missing from the Human skeleton.')
    rows = []
    clips = []
    sample_count = 0
    total_channels = 0
    for name in sorted(old.keys() & new.keys()):
        aclip, bclip = old[name], new[name]
        a, b = aclip['channels'], bclip['channels']
        if aclip['metadata'] != bclip['metadata']:
            errors.append('Animation metadata changed: ' + name)
        if a.keys() != b.keys():
            errors.append('Channel inventory changed: ' + name)
        clip_rows = []
        times_identical = True
        for key in sorted(a.keys() & b.keys()):
            total_channels += 1
            previous, current = a[key], b[key]
            same_input = before.record(previous['input']) == after.record(current['input'])
            sampler_metadata = [
                {k: v for k, v in sampler.items() if k not in ('input', 'output')}
                for sampler in (previous, current)]
            if not same_input or sampler_metadata[0] != sampler_metadata[1]:
                errors.append('Timestamp/interpolation change: ' + name + ' ' + str(key))
                times_identical = False
            if before.record(previous['output']) == after.record(current['output']):
                continue
            va, vb = before.values(previous['output']), after.values(current['output'])
            times = [value[0] for value in after.values(current['input'])]
            if len(va) != len(vb) or len(vb) != len(times):
                errors.append('Animation sample-count/shape change: ' + name + ' ' + str(key))
            if not all(math.isfinite(value) for sample in vb for value in sample):
                errors.append('Non-finite animation value: ' + name + ' ' + str(key))
            changed_samples = [index for index, pair in enumerate(zip(va, vb)) if pair[0] != pair[1]]
            changed_frames = [round(times[index] * 60) for index in changed_samples if index < len(times)]
            component_delta = max((abs(x - y) for ca, cb in zip(va, vb)
                                   for x, y in zip(ca, cb)), default=0.0)
            frame_scope = bool(changed_frames) and all(within_window(frame, window) for frame in changed_frames)
            bone_scope = name == RACK_CLIP and key[0] in bones and frame_scope
            roundoff_scope = name == RACK_CLIP and key[0] in roundoff_bones and frame_scope
            allowed = bone_scope and key[1] == 'rotation'
            row = {
                'clip': name, 'bone': key[0], 'property': key[1],
                'sample_count': len(vb), 'changed_samples': len(changed_samples),
                'changed_frames': changed_frames,
                'within_reviewed_rack_frame_window': frame_scope,
                'maximum_absolute_component_difference': component_delta,
                'change_class': 'reviewed_rack_left_rotation' if allowed else 'unexpected',
                'intentional_rotation_change': allowed,
                'unchanged_source_rotation_roundoff': False,
                'rest_bounded_decomposition_roundoff': False,
            }
            if key[1] == 'rotation':
                row['maximum_orientation_difference_degrees'] = max(
                    (qangle(x, y) for x, y in zip(va, vb)), default=0.0)
                if roundoff_scope:
                    norm_error = max((abs(math.hypot(*value) - 1.0) for value in va + vb), default=0.0)
                    numeric_ok = (row['maximum_orientation_difference_degrees'] <= rotation_roundoff_limit
                                  and component_delta <= QUATERNION_COMPONENT_ROUNDOFF and norm_error <= 2e-6)
                    row.update({'unchanged_source_rotation_roundoff': numeric_ok,
                                'rotation_roundoff_limit_degrees': rotation_roundoff_limit,
                                'quaternion_component_roundoff_limit': QUATERNION_COMPONENT_ROUNDOFF,
                                'maximum_unit_quaternion_norm_error': norm_error})
                    if numeric_ok:
                        allowed = True
                        row['change_class'] = 'reviewed_unchanged_source_finger_rotation_roundoff'
            if allow_roundoff and (bone_scope or roundoff_scope) and key[1] in ROUND_OFF_LIMITS:
                default = [0.0, 0.0, 0.0] if key[1] == 'translation' else [1.0, 1.0, 1.0]
                rest_old = old_nodes[key[0]].get(key[1], default)
                rest_new = new_nodes[key[0]].get(key[1], default)
                old_error = max((abs(value - rest) for values in va
                                 for value, rest in zip(values, rest_old)), default=0.0)
                new_error = max((abs(value - rest) for values in vb
                                 for value, rest in zip(values, rest_new)), default=0.0)
                limit = ROUND_OFF_LIMITS[key[1]]
                numeric_ok = rest_old == rest_new and max(component_delta, old_error, new_error) <= limit
                row.update({'rest_bounded_decomposition_roundoff': numeric_ok,
                            'roundoff_limit': limit,
                            'baseline_maximum_rest_deviation': old_error,
                            'candidate_maximum_rest_deviation': new_error})
                if numeric_ok:
                    allowed = True
                    row['change_class'] = 'reviewed_rest_bounded_decomposition_roundoff'
            row['allowed'] = allowed
            if not allowed:
                errors.append('Unexpected changed channel: ' + name + ' ' + str(key))
            rows.append(row)
            clip_rows.append(row)
        first = next(iter(b.values()), None)
        frames = after.record(first['input'])['count'] if first else 0
        sample_count += frames
        clips.append({'clip': name, 'sample_count': frames, 'channel_count': len(b),
                      'timestamps_and_interpolation_identical': times_identical,
                      'all_outputs_byte_identical': not clip_rows,
                      'changed_channels': [row['bone'] + ':' + row['property'] for row in clip_rows]})
    return {
        'clip_count': len(clips), 'inclusive_sample_count': sample_count,
        'total_channels': total_channels, 'clips': clips, 'changed_channels': rows,
        'all_non_rack_outputs_byte_identical': not any(row['clip'] != RACK_CLIP for row in rows),
        'all_right_side_outputs_byte_identical': not any(row['bone'].startswith('Right') for row in rows),
        'all_non_left_outputs_byte_identical': not any(not row['bone'].startswith('Left') for row in rows),
        'actual_changed_rotation_bones': sorted({row['bone'] for row in rows if row['property'] == 'rotation'}),
        'intentional_changed_rotation_bones': sorted({row['bone'] for row in rows if row['intentional_rotation_change']}),
        'roundoff_only_changed_rotation_bones': sorted({row['bone'] for row in rows if row['unchanged_source_rotation_roundoff']}),
        'maximum_unchanged_source_rotation_roundoff_degrees': max(
            (row['maximum_orientation_difference_degrees'] for row in rows
             if row['unchanged_source_rotation_roundoff']), default=0.0),
        'maximum_unchanged_source_quaternion_component_roundoff': max(
            (row['maximum_absolute_component_difference'] for row in rows
             if row['unchanged_source_rotation_roundoff']), default=0.0),
        'actual_changed_frame_range': [
            min((f for row in rows for f in row['changed_frames']), default=None),
            max((f for row in rows for f in row['changed_frames']), default=None)],
        'nonrotation_changes': [row for row in rows if row['property'] != 'rotation'],
    }


def compare_authored_frames(baseline, candidate, bones, window, errors):
    name = 'validation/AUTHORED_FRAMES.json'
    old, new = load(baseline / name), load(candidate / name)
    allow_station = bool(bones & ARM_BONES)
    allowed_top = {'maximum_wrist_error_metres', 'maximum_reach_fraction'} if allow_station else set()
    top_changed = [key for key in old.keys() | new.keys() if key != 'clips' and old.get(key) != new.get(key)]
    if set(top_changed) - allowed_top:
        errors.append('Authored-frame metadata changed outside left-station metric scope.')
    if new.get('passed') is not True:
        errors.append('Candidate authored-frame report is not passing.')
    if old['clips'].keys() != new['clips'].keys():
        errors.append('Authored-frame clip inventory changed.')
    changed = []
    count = 0
    for action in sorted(old['clips'].keys() & new['clips'].keys()):
        a, b = old['clips'][action], new['clips'][action]
        metadata = [{k: v for k, v in clip.items() if k != 'samples'} for clip in (a, b)]
        if metadata[0] != metadata[1] or len(a['samples']) != len(b['samples']):
            errors.append('Authored-frame timing/count changed: ' + action)
        for before, after in zip(a['samples'], b['samples']):
            count += 1
            if before == after:
                continue
            fields = [key for key in before.keys() | after.keys()
                      if before.get(key) != after.get(key)]
            only_left = (action == 'rack' and allow_station and
                         within_window(after['frame'], window))
            if only_left:
                if set(fields) - {'arms', 'left_hand_blender'}:
                    only_left = False
                old_arms, new_arms = before.get('arms', {}), after.get('arms', {})
                if old_arms.keys() != new_arms.keys() or old_arms.get('Right') != new_arms.get('Right'):
                    only_left = False
            row = {'action': action, 'frame': after['frame'], 'changed_fields': fields,
                   'allowed_left_station_only': only_left}
            changed.append(row)
            if not only_left:
                errors.append('Unexpected authored-frame choreography change: ' + action + ' ' + str(after['frame']))
    return {'sample_count': count, 'left_station_changes_allowed': allow_station,
            'changed_rows': changed, 'changed_summary_fields': top_changed,
            'all_rows_identical': not changed,
            'baseline_sha256': sha(baseline / name), 'candidate_sha256': sha(candidate / name)}


def preserved_files(baseline):
    names = {
        'Human.r11.glb', 'PX9_Eclipse_FP.glb', 'PX9_Eclipse_FP_RestSpace.glb',
        'Human.px9_eclipse.body.res', 'Human.px9_eclipse.hand_weights.json',
        'item_px9.json', 'item_px9_rest_space.json', 'project.godot',
        'render_first_person.tscn', 'LICENSE.txt', 'THIRD_PARTY_NOTICES.txt',
        'TEXTURE_PROVENANCE.json', 'CLIPS.txt',
    }
    names.update(path.name for path in baseline.glob('*.gd'))
    for directory in ('textures', 'textures_source', 'reference'):
        names.update(str(path.relative_to(baseline)) for path in (baseline / directory).rglob('*')
                     if path.is_file() and '__pycache__' not in path.parts)
    names.update(str(path.relative_to(baseline)) for path in (baseline / 'source').rglob('*')
                 if path.is_file() and path.suffix in {'.py', '.gd', '.json'}
                 and '__pycache__' not in path.parts and path.name != 'px9_motion.py')
    return names


def compare_native_import(baseline, candidate, errors):
    name = 'ANIMATION_IMPORT_REPORT.json'
    old, new = load(baseline / name), load(candidate / name)
    skin = new.get('hand_skin_variant', {})
    checks = {
        'native_import_passed': new.get('passed') is True,
        'human_animation_source_hash_current': new.get('animation_source_sha256') == sha(candidate / 'Human.px9_eclipse.glb'),
        'definition_hash_current': new.get('definition_sha256') == sha(candidate / 'item_px9.json'),
        'animation_library_hash_current': new.get('output_sha256') == sha(candidate / 'Human.px9_eclipse.res'),
        'reference_model_hash_current': new.get('reference_sha256') == sha(candidate / 'Human.r11.glb'),
        'original_reference_model_unmodified': new.get('reference_model_modified') is False,
        'native_skin_variant_passed': skin.get('passed') is True,
        'native_skin_patch_hash_current': skin.get('source_patch_sha256') == sha(candidate / 'source/hand_weight_patch.json'),
        'native_body_hash_current': skin.get('output_sha256') == sha(candidate / 'Human.px9_eclipse.body.res'),
        'native_geometry_and_morph_buffers_preserved': skin.get('raw_geometry_and_morph_buffers_byte_identical') is True,
        'native_saved_geometry_buffers_preserved': skin.get('saved_geometry_buffers_byte_identical') is True,
        'native_saved_skin_buffers_match': skin.get('saved_skin_buffers_match_variant') is True,
        'native_nonhand_weights_preserved': skin.get('original_native_non_hand_weights_preserved') is True,
        'native_unpatched_skin_records_preserved': skin.get('unpatched_skin_records_byte_identical') is True,
        'source_runtime_skin_patch_identical': sha(candidate / 'source/hand_weight_patch.json') == sha(candidate / 'Human.px9_eclipse.hand_weights.json'),
        'native_clip_metadata_timing_events_identical': old.get('clips') == new.get('clips'),
        'native_skin_report_identical': old.get('hand_skin_variant') == new.get('hand_skin_variant'),
        'native_rest_validation_identical': old.get('rest_validation') == new.get('rest_validation'),
    }
    for key in ('fps', 'original_animation_count', 'target_skeleton_path', 'track_policy',
                'source_carrier_mesh_used_at_runtime', 'animation_player_root'):
        checks['unchanged_' + key] = old.get(key) == new.get(key)
    failures = [key for key, value in checks.items() if not value]
    if failures:
        errors.append('Native import freshness/contract failure: ' + ', '.join(failures))
    return checks


def compare(baseline, candidate, bones, window=(0, 72), allow_roundoff=False,
            require_change=True, source_reviews=None, roundoff_bones=frozenset(),
            rotation_roundoff_limit=ROTATION_ROUNDOFF_DEGREES, source_roundoff_proof=None):
    if not bones or not bones <= ALLOWED_BONES:
        raise ValueError('The explicit edit scope must be a nonempty subset of left hand/arm bones.')
    if len(window) != 2 or window[0] < 0 or window[1] > 72 or window[0] > window[1]:
        raise ValueError('Rack edit window must be an inclusive interval within frames 0–72.')
    source_reviews = source_reviews or {}
    if not roundoff_bones <= NONTHUMB_FINGER_BONES or roundoff_bones & bones:
        raise ValueError('Roundoff-only nodes must be non-thumb left fingers, disjoint from intentional rotation nodes.')
    if not 0 < rotation_roundoff_limit <= ROTATION_ROUNDOFF_DEGREES:
        raise ValueError('The unchanged-source rotation roundoff ceiling is 0.00003 degrees.')
    errors = []
    proof_review = None
    if roundoff_bones:
        if source_roundoff_proof is None:
            raise ValueError('Roundoff-only finger nodes require a saved-source local-key equality proof.')
        proof = load(source_roundoff_proof)
        proven_bones = {row['bone'] for row in proof.get('bones', [])
                        if row.get('all_local_source_keys_identical') is True
                        and row.get('curves') == 10 and row.get('samples_per_curve') == 73}
        proof_checks = {
            'expected_proof_schema': proof.get('schema') == 'px9-rack-local-source-equality-1',
            'proof_passed': proof.get('passed') is True,
            'all_source_local_keys_identical': proof.get('all_local_source_keys_identical') is True,
            'source_files_unmodified_by_inspection': proof.get('input_files_unmodified') is True,
            'all_roundoff_bones_proven': roundoff_bones <= proven_bones,
            'baseline_blender_hash_current': proof.get('baseline_source_sha256') == sha(baseline / 'source/Human.px9_eclipse.blend'),
            'candidate_blender_hash_current': proof.get('candidate_source_sha256') == sha(candidate / 'source/Human.px9_eclipse.blend'),
        }
        proof_review = {'path': str(Path(source_roundoff_proof).resolve()),
                        'sha256': sha(source_roundoff_proof), 'checks': proof_checks}
        if not all(proof_checks.values()):
            errors.append('Saved-source local-key equality proof is missing, failed or stale.')
    filename = 'Human.px9_eclipse.glb'
    before, after = GLB(baseline / filename), GLB(candidate / filename)
    fixed_before, fixed_after = before.fixed_content(), after.fixed_content()
    fixed_differences = [key for key in fixed_before.keys() | fixed_after.keys()
                         if fixed_before.get(key) != fixed_after.get(key)]
    if fixed_differences:
        errors.append('Human GLB mesh/rest/bind/material fixed content changed: ' + ', '.join(sorted(fixed_differences)))
    animation = compare_animations(before, after, bones, window, allow_roundoff, errors,
                                   roundoff_bones, rotation_roundoff_limit)
    if require_change and not any(row['change_class'] == 'reviewed_rack_left_rotation'
                                  for row in animation['changed_channels']):
        errors.append('No allowed Rack left-hand rotation changed.')
    if animation['clip_count'] != 20 or animation['inclusive_sample_count'] != 1582:
        errors.append('Expected 20 paired human clips and 1,582 inclusive authored samples.')
    authored = compare_authored_frames(baseline, candidate, bones, window, errors)
    files = []
    exact_sources = []
    for relative in sorted(preserved_files(baseline)):
        a, b = baseline / relative, candidate / relative
        if not a.is_file() or not b.is_file():
            errors.append('Missing preservation input: ' + relative)
            continue
        ha, hb = sha(a), sha(b)
        identical = ha == hb
        row = {'file': relative, 'baseline_sha256': ha, 'candidate_sha256': hb, 'identical': identical}
        if relative in source_reviews:
            review = source_reviews[relative]
            # No runtime, weight, geometry, skeleton or patch exemptions here.
            if relative != 'source/author_px9_first_person.py':
                raise ValueError('Only the author call-site may have an explicit source hash review.')
            valid = (review.get('baseline_sha256') == ha and review.get('candidate_sha256') == hb
                     and isinstance(review.get('reason'), str) and bool(review['reason'].strip()))
            row['reviewed_callsite_change'] = valid
            row['reason'] = review.get('reason')
            exact_sources.append(row)
            if not valid:
                errors.append('Author call-site revision differs from its reviewed exact hashes.')
        elif not identical:
            errors.append('Protected file changed: ' + relative)
        files.append(row)
    unknown_source_reviews = set(source_reviews) - {'source/author_px9_first_person.py'}
    if unknown_source_reviews:
        raise ValueError('Unsupported source review file(s): ' + ', '.join(sorted(unknown_source_reviews)))
    stats_before, stats_after = load(baseline / 'ASSET_STATS.json'), load(candidate / 'ASSET_STATS.json')
    stat_keys = ('license', 'fps', 'paired_clip_count', 'source_actions_new',
                 'inclusive_frame_samples_per_rig', 'native_review_display_frames', 'weapon', 'human')
    stats_checks = {key: stats_before.get(key) == stats_after.get(key) for key in stat_keys}
    if not all(stats_checks.values()):
        errors.append('Asset topology/clip inventory stats changed: ' + ', '.join(k for k, v in stats_checks.items() if not v))
    native = compare_native_import(baseline, candidate, errors)
    motion = {'file': 'source/px9_motion.py',
              'baseline_sha256': sha(baseline / 'source/px9_motion.py'),
              'candidate_sha256': sha(candidate / 'source/px9_motion.py')}
    return {
        'schema': 'px9-rack-left-export-regression-1', 'passed': not errors, 'errors': errors,
        'baseline': str(baseline), 'candidate': str(candidate),
        'scope': __doc__.strip(),
        'reviewed_rack_rotation_bones': sorted(bones), 'reviewed_rack_frame_window': list(window),
        'reviewed_roundoff_only_finger_bones': sorted(roundoff_bones),
        'unchanged_source_rotation_roundoff_limit_degrees': rotation_roundoff_limit if roundoff_bones else None,
        'unchanged_source_rotation_roundoff_component_limit': QUATERNION_COMPONENT_ROUNDOFF if roundoff_bones else None,
        'source_roundoff_proof': proof_review,
        'rest_bounded_decomposition_roundoff_allowed': allow_roundoff,
        'roundoff_limits': ROUND_OFF_LIMITS if allow_roundoff else {},
        'baseline_human_glb_sha256': sha(baseline / filename),
        'candidate_human_glb_sha256': sha(candidate / filename),
        'human_fixed_content_identical': not fixed_differences,
        'human_fixed_content_differences': sorted(fixed_differences),
        'animations': animation, 'authored_frames': authored,
        'preserved_files': files, 'asset_stats_checks': stats_checks,
        'native_import_checks': native, 'motion_source_revision': motion,
        'explicit_author_callsite_reviews': exact_sources,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--rotation-bones', default=','.join(sorted(FINGER_BONES)),
                        help='Comma-separated exact left finger/arm rotation node allowlist.')
    parser.add_argument('--frame-start', type=int, default=0)
    parser.add_argument('--frame-end', type=int, default=72)
    parser.add_argument('--allow-rest-roundoff', action='store_true',
                        help='Allow <=1µm translation and <=2e-6 scale decomposition noise only on the reviewed Rack bones, with both versions still within the same bounds of unchanged rest.')
    parser.add_argument('--roundoff-bones', default='',
                        help='Separate non-thumb left finger nodes whose source local keys are proven identical; these nodes receive only the tight numeric-noise allowance, not intentional rotation permission.')
    parser.add_argument('--rotation-roundoff-degrees', type=float, default=ROTATION_ROUNDOFF_DEGREES,
                        help='Normalized quaternion noise ceiling, no greater than 0.00003 degrees.')
    parser.add_argument('--source-roundoff-proof', type=Path,
                        help='Fresh compare_rack_source_curves.py report required for --roundoff-bones.')
    parser.add_argument('--source-review', type=Path,
                        help='Optional JSON map of exact old/new author call-site hashes and reason.')
    parser.add_argument('--identity-check', action='store_true',
                        help='Reader smoke check only: do not require a changed Rack rotation.')
    args = parser.parse_args()
    bones = {value.strip() for value in args.rotation_bones.split(',') if value.strip()}
    roundoff_bones = {value.strip() for value in args.roundoff_bones.split(',') if value.strip()}
    review = load(args.source_review) if args.source_review else None
    report = compare(args.baseline.resolve(), args.candidate.resolve(), bones,
                     (args.frame_start, args.frame_end), args.allow_rest_roundoff,
                     not args.identity_check, review, roundoff_bones,
                     args.rotation_roundoff_degrees, args.source_roundoff_proof)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print(json.dumps({
        'passed': report['passed'], 'report': str(args.report),
        'errors': report['errors'],
        'clip_count': report['animations']['clip_count'],
        'inclusive_sample_count': report['animations']['inclusive_sample_count'],
        'changed_rotation_bones': report['animations']['actual_changed_rotation_bones'],
        'intentional_changed_rotation_bones': report['animations']['intentional_changed_rotation_bones'],
        'roundoff_only_changed_rotation_bones': report['animations']['roundoff_only_changed_rotation_bones'],
        'maximum_unchanged_source_rotation_roundoff_degrees': report['animations']['maximum_unchanged_source_rotation_roundoff_degrees'],
        'changed_frame_range': report['animations']['actual_changed_frame_range'],
        'nonrotation_changed_channel_count': len(report['animations']['nonrotation_changes']),
        'all_non_rack_outputs_byte_identical': report['animations']['all_non_rack_outputs_byte_identical'],
        'all_non_left_outputs_byte_identical': report['animations']['all_non_left_outputs_byte_identical'],
        'human_fixed_content_identical': report['human_fixed_content_identical'],
        'protected_file_count': len(report['preserved_files']),
    }, indent=2))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
