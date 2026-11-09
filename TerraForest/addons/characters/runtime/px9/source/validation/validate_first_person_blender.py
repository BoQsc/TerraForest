# SPDX-License-Identifier: CC0-1.0
"""Independent, read-only source checks for the PX9 / Human R11 FP handoff.

Run with Blender against Human.px9_eclipse.blend and pass -- followed by:
  --manifest item_px9.json --reference-human original_r11_contract.json
  --reference-weapon original_px9_contract.json --report FP_BLENDER_VALIDATION.json

Uses only Python's standard library and Blender's bundled mathutils/bpy.
"""
from pathlib import Path
from array import array
import argparse
import hashlib
import json
import math
import re
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from hand_weight_eligibility import audit_hand_patch

parser = argparse.ArgumentParser()
parser.add_argument('--manifest', type=Path, required=True)
parser.add_argument('--reference-human', type=Path, default=HERE / 'original_r11_contract.json')
parser.add_argument('--reference-weapon', type=Path, default=HERE / 'original_px9_contract.json')
parser.add_argument('--report', type=Path, default=HERE / 'FP_BLENDER_VALIDATION.json')
parser.add_argument('--human-rig', default='Human_Rig')
parser.add_argument('--weapon-rig', default='WeaponSkeleton')
parser.add_argument('--body-variant', default='Human_FP_Hands')
parser.add_argument('--reference-body', type=Path, default=HERE / 'original_human_body_variant_contract.json')
parser.add_argument('--hand-patch', type=Path)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

human_reference = json.loads(args.reference_human.read_text())
weapon_reference = json.loads(args.reference_weapon.read_text())
body_reference = json.loads(args.reference_body.read_text())
definition = json.loads(args.manifest.read_text())
source = Path(bpy.data.filepath)
source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
errors = []
warnings = []
checks = {}


def check(name, condition, detail=None):
    checks[name] = bool(condition)
    if not condition:
        errors.append({'check': name, 'detail': detail})


def hash_json(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def action_record(action):
    curves = []
    for curve in sorted(action.fcurves, key=lambda c: (c.data_path, c.array_index)):
        curves.append({
            'path': curve.data_path, 'index': curve.array_index,
            'group': curve.group.name if curve.group else None,
            'extrapolation': curve.extrapolation,
            'keys': [[list(key.co), key.interpolation,
                      list(key.handle_left), list(key.handle_right),
                      key.handle_left_type, key.handle_right_type,
                      key.type, key.easing, key.amplitude, key.back, key.period]
                     for key in curve.keyframe_points],
            'modifiers': [modifier.type for modifier in curve.modifiers],
        })
    return {'frame_range': list(action.frame_range), 'fcurves': len(curves),
            'key_count': sum(len(curve['keys']) for curve in curves),
            'curve_content_sha256': hash_json(curves)}


def mesh_record(obj):
    mesh = obj.data
    vertices = array('f', [0.0]) * (len(mesh.vertices) * 3)
    mesh.vertices.foreach_get('co', vertices)
    indices = array('i', [0]) * len(mesh.loops)
    mesh.loops.foreach_get('vertex_index', indices)
    starts = array('i', [0]) * len(mesh.polygons)
    mesh.polygons.foreach_get('loop_start', starts)
    sizes = array('i', [0]) * len(mesh.polygons)
    mesh.polygons.foreach_get('loop_total', sizes)
    groups = {group.index: group.name for group in obj.vertex_groups}
    weights = [[(groups[group.group], group.weight) for group in vertex.groups]
               for vertex in mesh.vertices]
    mesh.calc_loop_triangles()
    uv_layers = []
    for layer in mesh.uv_layers:
        uv_values = array('f', [0.0]) * (len(layer.data) * 2)
        layer.data.foreach_get('uv', uv_values)
        uv_layers.append({'name': layer.name, 'loops': len(layer.data),
                          'coordinates_sha256': hashlib.sha256(uv_values.tobytes()).hexdigest()})
    return {
        'vertices': len(mesh.vertices), 'polygons': len(mesh.polygons),
        'triangles': len(mesh.loop_triangles),
        'positions_sha256': hashlib.sha256(vertices.tobytes()).hexdigest(),
        'topology_sha256': hashlib.sha256(indices.tobytes() + starts.tobytes() + sizes.tobytes()).hexdigest(),
        'weights_sha256': hash_json(weights),
        'material_names': [slot.material.name if slot.material else None for slot in obj.material_slots],
        'uv_layers': uv_layers,
        'material_indices_sha256': hash_json([face.material_index for face in mesh.polygons]),
        'shape_names': [block.name for block in mesh.shape_keys.key_blocks] if mesh.shape_keys else [],
    }


def matrix_error(a, b):
    return max(abs(a[row][column] - b[row][column]) for row in range(4) for column in range(4))


def f32_hash(collection, attribute, width):
    values = array('f', [0.0]) * (len(collection) * width)
    collection.foreach_get(attribute, values)
    return hashlib.sha256(values.tobytes()).hexdigest()


def detailed_body_record(obj):
    mesh = obj.data
    return {
        'vertices': len(mesh.vertices),
        'positions_sha256': f32_hash(mesh.vertices, 'co', 3),
        'uv_layers': [{'name': layer.name, 'loops': len(layer.data),
                       'coordinates_sha256': f32_hash(layer.data, 'uv', 2)}
                      for layer in mesh.uv_layers],
        'shape_keys': [{'name': block.name, 'vertices': len(block.data),
                        'coordinates_sha256': f32_hash(block.data, 'co', 3),
                        'relative_key': block.relative_key.name,
                        'vertex_group': block.vertex_group,
                        'interpolation': block.interpolation}
                       for block in mesh.shape_keys.key_blocks] if mesh.shape_keys else [],
        'material_names': [slot.material.name if slot.material else None for slot in obj.material_slots],
    }


human = bpy.data.objects.get(args.human_rig)
weapon = bpy.data.objects.get(args.weapon_rig)
check('human_armature_present', human is not None and human.type == 'ARMATURE')
check('weapon_armature_present', weapon is not None and weapon.type == 'ARMATURE')
check('distinct_human_and_weapon_armatures', human is not None and weapon is not None and human != weapon)

rig_reports = {}
for label, obj, reference, count in [('human', human, human_reference, 59), ('weapon', weapon, weapon_reference, 22)]:
    if obj is None or obj.type != 'ARMATURE':
        continue
    names = set(obj.data.bones.keys())
    expected = set(reference['bones'])
    maximum_error = 0.0
    changed_parents = []
    changed_names = sorted(names.symmetric_difference(expected))
    for name in names.intersection(expected):
        bone = obj.data.bones[name]
        old = reference['bones'][name]
        maximum_error = max(maximum_error, matrix_error(bone.matrix_local, old['matrix_local']))
        if (bone.parent.name if bone.parent else None) != old['parent']:
            changed_parents.append(name)
    check(label + '_exact_bone_names_count', len(names) == count and not changed_names, changed_names)
    check(label + '_bone_parents_unchanged', not changed_parents, changed_parents)
    check(label + '_rest_matrices_exactly_unchanged', maximum_error == 0.0, maximum_error)
    rig_reports[label] = {'name': obj.name, 'bones': len(names),
                          'maximum_rest_matrix_component_error': maximum_error,
                          'changed_names': changed_names, 'changed_parents': changed_parents}

if human is not None:
    human_object_error = matrix_error(human.matrix_world, human_reference['armature_matrix'])
    check('human_armature_object_transform_unchanged', human_object_error <= 1e-8, human_object_error)

preserved_actions = []
missing_actions = []
changed_actions = []
for name, expected in human_reference['actions'].items():
    actual = bpy.data.actions.get(name)
    if actual is None:
        missing_actions.append(name)
    else:
        record = action_record(actual)
        if record != expected:
            changed_actions.append({'name': name, 'expected': expected, 'actual': record})
        else:
            preserved_actions.append(name)
check('all_497_original_source_actions_present', len(preserved_actions) + len(changed_actions) == 497 and not missing_actions, missing_actions)
check('all_497_original_source_actions_unchanged', len(preserved_actions) == 497 and not changed_actions, changed_actions[:10])
check('all_71_original_rig_clips_present', all(name in bpy.data.actions for name in human_reference['runtime_clips']))
missing_weapon_actions = [name for name in weapon_reference['action_names'] if name not in bpy.data.actions]
check('original_11_weapon_actions_present', not missing_weapon_actions, missing_weapon_actions)

mesh_reports = {}
for label, reference in [('human', human_reference), ('weapon', weapon_reference)]:
    missing = []
    changes = []
    records = {}
    for name, expected in reference['meshes'].items():
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != 'MESH':
            missing.append(name)
            continue
        current = mesh_record(obj)
        differing = [key for key in expected if current.get(key) != expected[key]]
        if differing:
            changes.append({'name': name, 'fields': differing})
        records[name] = current
    check(label + '_original_mesh_names_preserved', not missing, missing)
    check(label + '_mesh_geometry_weights_materials_preserved', not changes, changes)
    mesh_reports[label] = {'missing': missing, 'changes': changes, 'meshes': records}

# The optional first-person body changes hand weights only. Original Human_Body
# and all of its shape geometry must remain intact for every pre-existing item.
variant_report = {'name': args.body_variant, 'present': False}
original_body = bpy.data.objects.get('Human_Body')
variant = bpy.data.objects.get(args.body_variant)
check('separate_first_person_body_variant_present', variant is not None and variant.type == 'MESH')
if original_body is not None and original_body.type == 'MESH':
    original_deep = detailed_body_record(original_body)
    original_fields_changed = [name for name in original_deep if original_deep[name] != body_reference[name]]
    check('original_body_uv_and_all_229_shape_coordinates_preserved', not original_fields_changed, original_fields_changed)
    check('original_body_object_transform_preserved', matrix_error(original_body.matrix_world, body_reference['object_matrix_world']) <= 1e-8)
if variant is not None and variant.type == 'MESH' and original_body is not None:
    variant_report['present'] = True
    deep = detailed_body_record(variant)
    mesh = mesh_record(variant)
    expected_mesh = human_reference['meshes']['Human_Body']
    geometry_fields = ['vertices', 'polygons', 'triangles', 'positions_sha256',
                       'topology_sha256', 'material_names', 'shape_names']
    geometry_changed = [name for name in geometry_fields if mesh[name] != expected_mesh[name]]
    deep_fields_changed = [name for name in deep if deep[name] != body_reference[name]]
    check('variant_has_independent_mesh_data', variant.data != original_body.data)
    check('variant_positions_topology_and_materials_equal_original', not geometry_changed, geometry_changed)
    check('variant_uv_and_all_229_shape_coordinates_equal_original', not deep_fields_changed, deep_fields_changed)
    check('variant_object_transform_matches_original', matrix_error(variant.matrix_world, original_body.matrix_world) <= 1e-8)
    armature_modifiers = [modifier for modifier in variant.modifiers if modifier.type == 'ARMATURE']
    check('variant_bound_to_original_human_rig', len(armature_modifiers) == 1 and armature_modifiers[0].object == human)
    group_names = {group.index: group.name for group in variant.vertex_groups}
    check('variant_vertex_group_names_preserved', [group.name for group in variant.vertex_groups] == body_reference['vertex_group_names'])
    patch = json.loads(args.hand_patch.read_text()) if args.hand_patch else None
    eligibility_report = audit_hand_patch(patch, body_reference, human_reference, original_body) if patch else None
    allowed_exceptions = set(eligibility_report['reviewed_exception_vertices']) if eligibility_report else set()
    allowed_web_vertices = set(eligibility_report.get('reviewed_multi_family_vertices', [])) if eligibility_report else set()
    allowed_middle_ring_web_vertices = set(eligibility_report.get('reviewed_middle_ring_web_vertices', [])) if eligibility_report else set()
    if eligibility_report is not None:
        check('variant_patch_geometric_eligibility_and_narrow_exception', eligibility_report['passed'], eligibility_report['issues'][:20])
    changed = []
    non_hand_changes = []
    non_hand_influence_changes = []
    bad_weights = []
    variant_weights = []
    side_counts = {'Left': 0, 'Right': 0}
    minimum_hand_local_y = None
    minimum_original_hand_mass = None
    maximum_non_hand_influence_error = 0.0
    if len(variant.data.vertices) == body_reference['vertices']:
        hand_inverse = {side: Matrix(human_reference['bones'][side + 'Hand']['matrix_local']).inverted()
                        for side in ['Left', 'Right']}
        original_body_to_rig = Matrix(body_reference['rig_matrix_world']).inverted() @ Matrix(body_reference['object_matrix_world'])
        for vertex in variant.data.vertices:
            actual = {group_names[group.group]: group.weight for group in vertex.groups}
            original_weights = body_reference['weights'][vertex.index]
            variant_weights.append(actual)
            names = set(actual) | set(original_weights)
            weight_error = max((abs(actual.get(name, 0.0) - original_weights.get(name, 0.0)) for name in names), default=0.0)
            if weight_error <= 1e-7:
                continue
            changed.append(vertex.index)
            original_hand_mass = {side: sum(value for name, value in original_weights.items() if name.startswith(side + 'Hand'))
                                  for side in ['Left', 'Right']}
            side = max(original_hand_mass, key=original_hand_mass.get)
            mass = original_hand_mass[side]
            local = hand_inverse[side] @ original_body_to_rig @ Vector(body_reference['positions'][vertex.index])
            minimum_hand_local_y = local.y if minimum_hand_local_y is None else min(minimum_hand_local_y, local.y)
            minimum_original_hand_mass = mass if minimum_original_hand_mass is None else min(minimum_original_hand_mass, mass)
            if (mass < 0.5 - 1e-7 or local.y < 0.025 - 1e-7) and vertex.index not in allowed_exceptions:
                non_hand_changes.append({'vertex': vertex.index, 'side': side, 'original_hand_mass': mass, 'hand_local_y': local.y})
            side_counts[side] += 1
            other_names = [name for name in names if not name.startswith(side + 'Hand')]
            non_hand_error = max((abs(actual.get(name, 0.0) - original_weights.get(name, 0.0)) for name in other_names), default=0.0)
            maximum_non_hand_influence_error = max(maximum_non_hand_influence_error, non_hand_error)
            if non_hand_error > 1e-7:
                non_hand_influence_changes.append({'vertex': vertex.index, 'maximum_error': non_hand_error})
            active = {name: value for name, value in actual.items() if value > 1e-7}
            finger_families = set()
            invalid_hand_bones = []
            for name in active:
                if name.startswith(side + 'Hand') and name != side + 'Hand':
                    match = re.fullmatch(side + r'Hand(Index|Middle|Pinky|Ring|Thumb)[123]', name)
                    if match:
                        finger_families.add(match.group(1))
                    else:
                        invalid_hand_bones.append(name)
            if (len(active) > 4 or abs(sum(active.values()) - 1.0) > 1e-6
                    or any(not math.isfinite(value) or value < 0.0 for value in actual.values())
                    or (len(finger_families) > 1 and not (
                        (vertex.index in allowed_web_vertices and finger_families == {'Index', 'Middle'})
                        or (vertex.index == 4597 and vertex.index in allowed_middle_ring_web_vertices
                            and finger_families == {'Middle', 'Ring'})))
                    or invalid_hand_bones):
                bad_weights.append({'vertex': vertex.index, 'weights': actual, 'finger_families': sorted(finger_families),
                                    'invalid_hand_bones': invalid_hand_bones})
    check('variant_changes_at_least_one_hand_weight', bool(changed))
    check('variant_weight_changes_confined_to_hand_region', not non_hand_changes, non_hand_changes[:20])
    check('variant_preserves_all_non_hand_influences', not non_hand_influence_changes, non_hand_influence_changes[:20])
    check('variant_changed_weights_normalized_four_or_fewer_reviewed_finger_families', not bad_weights, bad_weights[:20])
    patch_report = {'checked': False}
    if args.hand_patch:
        patch_rows = patch.get('vertices', patch.get('rows', []))
        patch_issues = []
        seen = set()
        for row in patch_rows:
            index = int(row['vertex'])
            if index in seen or not 0 <= index < len(variant_weights):
                patch_issues.append({'vertex': index, 'issue': 'duplicate_or_out_of_range'})
                continue
            seen.add(index)
            expected_weights = {part['bone']: float(part['weight']) for part in row['weights']}
            expected_old = {part['bone']: float(part['weight']) for part in row['old_weights']}
            actual = variant_weights[index]
            original_weights = body_reference['weights'][index]
            for label, left, right in [('replacement', expected_weights, actual), ('original', expected_old, original_weights)]:
                error = max((abs(left.get(name, 0.0) - right.get(name, 0.0)) for name in set(left) | set(right)), default=0.0)
                if error > 1e-6:
                    patch_issues.append({'vertex': index, 'issue': label + '_mismatch', 'maximum_error': error})
            if (Vector(row['position_blender']) - Vector(body_reference['positions'][index])).length > 1e-7:
                patch_issues.append({'vertex': index, 'issue': 'reference_position_mismatch'})
        unlisted = sorted(set(changed) - seen)
        if unlisted:
            patch_issues.append({'issue': 'unlisted_changed_vertices', 'vertices': unlisted})
        check('variant_matches_portable_weight_patch', not patch_issues, patch_issues[:20])
        patch_report = {'checked': True, 'file': args.hand_patch.name, 'rows': len(patch_rows),
                        'sha256': hashlib.sha256(args.hand_patch.read_bytes()).hexdigest(), 'issues': patch_issues}
    variant_report.update({
        'vertices': len(variant.data.vertices), 'shape_blocks': len(deep['shape_keys']),
        'geometry_fields_changed': geometry_changed, 'uv_shape_fields_changed': deep_fields_changed,
        'changed_weight_vertices': len(changed), 'changed_vertex_indices': changed,
        'changed_by_side': side_counts,
        'minimum_original_hand_mass': minimum_original_hand_mass,
        'minimum_hand_rest_local_y_m': minimum_hand_local_y,
        'maximum_non_hand_influence_weight_error': maximum_non_hand_influence_error,
        'hand_region_rule': 'Original selected-side Hand-prefix influence mass >= 0.5 and Hand-rest-local Y >= 0.025 metres. Standard rows retain own-finger distance/arc limits; revision3 central-palm rows must independently satisfy the fixed palm box and source-derived interpolation. Only reviewed proximal web vertices444/479 may mix Index/Middle root families, with exact source adjacency and bounded weights. Revision 4 permits only source vertices 3, 9, 109, 118, 121, 123, and 125 to switch to the Middle chain, independently bounded by original rest positions, source Middle-family majority, exact adjacency and 27 source polygons, and Middle2/3 interpolation; every revision 3 and revision 2 row must remain exactly recoverable. Seam741 retains independently checked neighbor742 proportions. Existing non-hand influence values remain unchanged.',
        'geometric_eligibility': eligibility_report,
        'non_hand_changes': non_hand_changes, 'non_hand_influence_changes': non_hand_influence_changes,
        'invalid_weight_rows': bad_weights, 'patch': patch_report,
    })

if weapon is not None:
    skinned_parts = [obj for obj in bpy.data.objects if obj.type == 'MESH'
                     and any(modifier.type == 'ARMATURE' and modifier.object == weapon
                             for modifier in obj.modifiers)]
    triangle_count = sum(len(obj.data.loop_triangles) for obj in skinned_parts)
    check('weapon_17_separate_meshes', len(skinned_parts) == 17, [obj.name for obj in skinned_parts])
    check('weapon_19616_triangles_under_20000', triangle_count == 19616 and triangle_count < 20000, triangle_count)
    invalid_weights = []
    for obj in skinned_parts:
        for vertex in obj.data.vertices:
            active = [group for group in vertex.groups if group.weight > 0.0]
            if len(active) != 1 or abs(active[0].weight - 1.0) > 1e-7:
                invalid_weights.append([obj.name, vertex.index])
    check('weapon_rigid_unit_weights', not invalid_weights, invalid_weights[:20])

expected_images = ['PX9_Skeleton_BaseColor', 'PX9_Skeleton_Normal', 'PX9_Skeleton_ORM']
image_records = {}
for name in expected_images:
    image = bpy.data.images.get(name)
    expected = weapon_reference['images'][name]
    row = {'present': image is not None}
    if image is not None:
        row.update({'size': list(image.size), 'packed': bool(image.packed_file),
                    'packed_sha256': hashlib.sha256(image.packed_file.data).hexdigest() if image.packed_file else None})
    row['unchanged'] = row.get('size') == expected['size'] and row.get('packed_sha256') == expected['packed_sha256']
    image_records[name] = row
check('runtime_pbr_images_packed_and_unchanged', all(row['unchanged'] and row.get('packed') for row in image_records.values()), image_records)

scene = bpy.context.scene
check('scene_exactly_60_fps', scene.render.fps == 60 and scene.render.fps_base == 1.0,
      {'fps': scene.render.fps, 'fps_base': scene.render.fps_base})
check('definition_20_unique_clips', len(definition['actions']) == 20 and len({row['id'] for row in definition['actions']}) == 20)
check('definition_60_fps', definition['fps'] == 60 and all(row['fps'] == 60 for row in definition['actions']))
ids = {row['id'] for row in definition['actions']}
event_issues = []
for row in definition['actions']:
    end = row['frame_end']
    if row.get('return_action') and row['return_action'] not in ids:
        event_issues.append({'clip': row['id'], 'invalid_return': row['return_action']})
    for event in row.get('events', []):
        if not isinstance(event['frame'], int) or not 0 <= event['frame'] <= end:
            event_issues.append({'clip': row['id'], 'invalid_event': event})
check('event_frames_and_return_actions_resolve', not event_issues, event_issues)

pattern = re.compile(r'^pose\.bones\["([^"\\]+)"\]\.(location|rotation_quaternion|scale)$')
channel_sizes = {'location': 3, 'rotation_quaternion': 4, 'scale': 3}
stationary_bones = ['Root', 'Hips', 'LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase',
                    'RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase',
                    'Weapon_Pickaxe', 'Weapon_Axe', 'Weapon_Carbine', 'Weapon_Magazine']
clip_reports = []
for row in definition['actions']:
    frame_end = int(row['frame_end'])
    frames = list(range(frame_end + 1))
    for role, key, rig in [('human', 'human_action', human), ('weapon', 'weapon_action', weapon)]:
        name = row[key]
        action = bpy.data.actions.get(name)
        if action is None or rig is None:
            check(role + '_action_exists_' + row['id'], False, name)
            continue
        channels = {}
        invalid_paths = []
        frame_coverage_issues = []
        nonfinite_curves = []
        interpolation_issues = []
        for curve in action.fcurves:
            match = pattern.match(curve.data_path)
            if not match or match.group(1) not in rig.data.bones or curve.array_index >= channel_sizes.get(match.group(2), 0):
                invalid_paths.append([curve.data_path, curve.array_index])
                continue
            bone, property_name = match.groups()
            channel_key = (bone, property_name, curve.array_index)
            channels[channel_key] = curve
            key_frames = [float(key.co.x) for key in curve.keyframe_points]
            if key_frames != frames:
                frame_coverage_issues.append({'path': curve.data_path, 'index': curve.array_index,
                                              'key_count': len(key_frames), 'first_last': [key_frames[0], key_frames[-1]] if key_frames else []})
            if any(not math.isfinite(float(key.co.y)) for key in curve.keyframe_points):
                nonfinite_curves.append([curve.data_path, curve.array_index])
            if any(key.interpolation != 'LINEAR' for key in curve.keyframe_points):
                interpolation_issues.append([curve.data_path, curve.array_index])
        expected_channels = {(bone.name, prop, index) for bone in rig.data.bones
                             for prop, size in channel_sizes.items() for index in range(size)}
        missing_channels = sorted(expected_channels - channels.keys())
        duplicate_channel_count = len(action.fcurves) - len(channels) - len(invalid_paths)
        quaternion_errors = []
        scale_errors = []
        stationary_error = 0.0
        loop_error = 0.0
        if not missing_channels and not invalid_paths and not nonfinite_curves:
            for bone in rig.data.bones:
                loc = [channels[(bone.name, 'location', index)] for index in range(3)]
                rot = [channels[(bone.name, 'rotation_quaternion', index)] for index in range(4)]
                scale = [channels[(bone.name, 'scale', index)] for index in range(3)]
                first_matrix = None
                previous_q = None
                for frame in frames:
                    position = Vector([curve.evaluate(frame) for curve in loc])
                    q = Quaternion([curve.evaluate(frame) for curve in rot])
                    size = Vector([curve.evaluate(frame) for curve in scale])
                    if abs(q.magnitude - 1.0) > 1e-4:
                        quaternion_errors.append({'bone': bone.name, 'frame': frame, 'norm': q.magnitude})
                    if previous_q is not None and previous_q.dot(q) < -1e-7:
                        quaternion_errors.append({'bone': bone.name, 'frame': frame, 'hemisphere_dot': previous_q.dot(q)})
                    previous_q = q
                    if min(size) <= 0.0:
                        scale_errors.append({'bone': bone.name, 'frame': frame, 'scale': list(size)})
                    matrix = Matrix.LocRotScale(position, q, size)
                    if first_matrix is None:
                        first_matrix = matrix
                    if role == 'human' and bone.name in stationary_bones:
                        stationary_error = max(stationary_error, matrix_error(matrix, human_reference['idle_frame_1'][bone.name]['basis']))
                    if frame == frame_end and row['loop']:
                        loop_error = max(loop_error, matrix_error(matrix, first_matrix))
        passed = (not invalid_paths and not missing_channels and not frame_coverage_issues
                  and not nonfinite_curves and not interpolation_issues
                  and not quaternion_errors and not scale_errors and not duplicate_channel_count
                  and stationary_error <= 1e-5 and loop_error <= 1e-5)
        details = {
            'role': role, 'id': row['id'], 'action': name, 'frame_start': 0,
            'frame_end': frame_end, 'inclusive_frames': len(frames), 'fps': 60,
            'duration_seconds': frame_end / 60.0, 'loop': row['loop'],
            'curve_count': len(action.fcurves), 'expected_curve_count': len(expected_channels),
            'invalid_paths': invalid_paths[:10], 'missing_channels': missing_channels[:10],
            'duplicate_channel_count': duplicate_channel_count,
            'frame_coverage_issues': frame_coverage_issues[:10],
            'nonfinite_curves': nonfinite_curves[:10],
            'interpolation_issues': interpolation_issues[:10],
            'quaternion_issues': quaternion_errors[:10], 'scale_issues': scale_errors[:10],
            'maximum_stationary_baseline_matrix_error': stationary_error,
            'maximum_loop_endpoint_matrix_error': loop_error,
            'passed': passed,
        }
        clip_reports.append(details)
        check(role + '_per_frame_contract_' + row['id'], passed, details if not passed else None)

check('source_bytes_unmodified_by_inspection', hashlib.sha256(source.read_bytes()).hexdigest() == source_sha)
report = {
    'schema': 'px9-first-person-source-validation-1',
    'passed': not errors, 'errors': errors, 'warnings': warnings, 'checks': checks,
    'blender_version': bpy.app.version_string,
    'source_file': source.name, 'source_sha256_before': source_sha,
    'source_sha256_after': hashlib.sha256(source.read_bytes()).hexdigest(),
    'definition_file': args.manifest.name,
    'definition_sha256': hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
    'rigs': rig_reports,
    'original_actions': {'expected': 497, 'preserved': len(preserved_actions),
                         'missing': missing_actions, 'changed': changed_actions},
    'meshes': mesh_reports,
    'first_person_body_variant': variant_report,
    'images': image_records,
    'clips': clip_reports,
    'total_inclusive_frames_per_rig': sum(row['frame_end'] + 1 for row in definition['actions']),
    'stationary_human_bones': stationary_bones,
    'lower_body_policy': 'Original Idle frame1 remains constant in source; runtime FP import must strip lower-body tracks so locomotion retains control.',
    'scope': 'Read-only source preservation, rest identity, PBR-image identity, mesh skin identity and every-integer-frame animation data checks. Does not certify perceived motion/anatomy quality, contact collision, native playback or target-hardware performance.',
}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('PX9_FIRST_PERSON_SOURCE_VALIDATION', json.dumps({
    'passed': report['passed'], 'checks': len(checks), 'failed': [name for name, passed in checks.items() if not passed],
    'original_actions_preserved': len(preserved_actions), 'clip_records': len(clip_reports),
    'inclusive_frames_per_rig': report['total_inclusive_frames_per_rig'],
    'report': str(args.report),
}))
if errors:
    raise RuntimeError('PX9 first-person source validation failed; see report')
