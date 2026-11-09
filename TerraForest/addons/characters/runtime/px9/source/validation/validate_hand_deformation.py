# SPDX-License-Identifier: CC0-1.0
"""Read-only, every-source-frame hand deformation comparison.

Run with Blender -b Human.px9_eclipse.blend --python this_file --
  --manifest item_px9.json --patch hand_weight_patch.json --report report.json

Both skins are evaluated natively under the ACTUAL saved action of each
frame: the delivered skin and an in-memory copy with recovered revision-2
weights. This separates skin changes from changes to the animation poses.
It measures edge strain, not visual correctness, hand collisions or anatomy.
The script never saves or overwrites the supplied .blend.
"""
import argparse
import hashlib
import json
import math
import sys
from array import array
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))
from human_hand_skin_revision import frozen_revision_2
from human_hand_weights import apply_hand_patch
from hand_weight_eligibility import audit_hand_patch

parser = argparse.ArgumentParser()
parser.add_argument('--manifest', required=True, type=Path)
parser.add_argument('--patch', required=True, type=Path)
parser.add_argument('--report', required=True, type=Path)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
source = Path(bpy.data.filepath)
if not source.is_file():
    raise ValueError('Open the actual saved source .blend before running this audit.')
definition = json.loads(args.manifest.read_text())
patch = json.loads(args.patch.read_text())
body_reference = json.loads((HERE / 'original_human_body_variant_contract.json').read_text())
human_reference = json.loads((HERE / 'original_r11_contract.json').read_text())
scene = bpy.context.scene
rig = bpy.data.objects['Human_Rig']
body = bpy.data.objects['Human_Body']
variant = bpy.data.objects['Human_FP_Hands']


def weights(obj):
    return [{obj.vertex_groups[group.group].name: float(group.weight) for group in vertex.groups}
            for vertex in obj.data.vertices]


def f32_hash(collection, attribute, width):
    values = array('f', [0.0]) * (len(collection) * width)
    collection.foreach_get(attribute, values)
    return hashlib.sha256(values.tobytes()).hexdigest()


def deep_record(obj):
    mesh = obj.data
    return {
        'vertices': len(mesh.vertices), 'positions_sha256': f32_hash(mesh.vertices, 'co', 3),
        'uv_layers': [{'name': layer.name, 'loops': len(layer.data),
                       'coordinates_sha256': f32_hash(layer.data, 'uv', 2)} for layer in mesh.uv_layers],
        'shape_keys': [{'name': block.name, 'vertices': len(block.data),
                        'coordinates_sha256': f32_hash(block.data, 'co', 3),
                        'relative_key': block.relative_key.name, 'vertex_group': block.vertex_group,
                        'interpolation': block.interpolation} for block in mesh.shape_keys.key_blocks],
        'material_names': [slot.material.name if slot.material else None for slot in obj.material_slots],
    }


original = deep_record(body)
original_weights = weights(body)
invariants = {
    'original_body_rest_uv_all229_morphs_materials_equal_reference': all(body_reference[key] == value for key, value in original.items()),
    'original_body_weights_equal_reference': original_weights == body_reference['weights'],
    'variant_rest_uv_all229_morphs_materials_equal_original': deep_record(variant) == original,
    'variant_edges_faces_equal_original': (
        [tuple(edge.vertices) for edge in body.data.edges] == [tuple(edge.vertices) for edge in variant.data.edges]
        and [tuple(face.vertices) for face in body.data.polygons] == [tuple(face.vertices) for face in variant.data.polygons]),
}
eligibility = audit_hand_patch(patch, body_reference, human_reference, body)
invariants['independent_geometric_patch_eligibility'] = eligibility['passed']
row_map = {row['vertex']: row for row in patch['vertices']}
actual_weights = weights(variant)
maximum_nonhand_error = 0.0
maximum_patch_error = 0.0
unlisted = []
for index, (old, actual) in enumerate(zip(original_weights, actual_weights)):
    names = set(old) | set(actual)
    delta = max((abs(old.get(name, 0.0) - actual.get(name, 0.0)) for name in names), default=0.0)
    if index not in row_map:
        if delta > 1e-7:
            unlisted.append(index)
        continue
    row = row_map[index]
    expected = {part['bone']: part['weight'] for part in row['weights']}
    maximum_patch_error = max(maximum_patch_error, max((abs(actual.get(name, 0.0) - expected.get(name, 0.0))
                              for name in set(actual) | set(expected)), default=0.0))
    maximum_nonhand_error = max(maximum_nonhand_error, max((abs(old.get(name, 0.0) - actual.get(name, 0.0))
                                for name in names if not name.startswith(row['side'] + 'Hand')), default=0.0))
invariants['variant_matches_frozen_candidate'] = maximum_patch_error <= 1e-7 and not unlisted
invariants['original_nonhand_influences_unchanged'] = maximum_nonhand_error <= 1e-7
invariants['patched_vertices_four_or_fewer_active_influences'] = all(
    sum(value > 1e-7 for value in actual_weights[index].values()) <= 4 for index in row_map)
invariants['seam_neighbor742_untouched'] = actual_weights[742] == original_weights[742] and 742 not in row_map

# A private copy of the original mesh receives only the recovered old patch.
# This object and its data live solely in this read-only audit process.
baseline = body.copy()
baseline.data = body.data.copy()
baseline.name = 'AuditOnly_Revision2HandSkin'
bpy.context.scene.collection.objects.link(baseline)
baseline.hide_set(False)
baseline.hide_render = True
apply_hand_patch(baseline, rig, frozen_revision_2(patch))
for obj in (baseline, variant):
    if any(abs(block.value) > 1e-7 for block in obj.data.shape_keys.key_blocks):
        raise ValueError('Saved hand audit expects the bone-only item with neutral shape values.')

hand_vertices = {index for index, row in enumerate(original_weights)
                 if max(sum(value for name, value in row.items() if name.startswith(side + 'Hand'))
                        for side in ('Right', 'Left')) > .45}
palm_vertices = {row['vertex'] for row in patch['vertices'] if row['finger'] == 'Palm'}
web_vertices = {444, 479}
seam_vertices = {640, 741, 742}
rest = [body.matrix_world @ vertex.co for vertex in body.data.vertices]
edges = []
for edge in body.data.edges:
    a, b = edge.vertices
    if a not in hand_vertices and b not in hand_vertices:
        continue
    length = (rest[a] - rest[b]).length
    if length <= 1e-9:
        continue
    categories = ['all_hand']
    if a in palm_vertices or b in palm_vertices:
        categories.append('central_palm')
    if a in web_vertices or b in web_vertices:
        categories.append('proximal_index_middle_web')
    if a in seam_vertices or b in seam_vertices:
        categories.append('source_seam741')
    edges.append((a, b, length, categories))
category_names = ['all_hand', 'central_palm', 'proximal_index_middle_web', 'source_seam741']


def evaluate_positions(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    points = [obj.matrix_world @ vertex.co for vertex in mesh.vertices]
    evaluated.to_mesh_clear()
    return points


def summarize(points):
    data = {name: {'max_ratio': 0.0, 'min_ratio': float('inf'), 'edges_over_2x': 0,
                  'edges_over_3x': 0, 'edges_over_5x': 0, 'worst_edge': None} for name in category_names}
    ratios = []
    for a, b, length, categories in edges:
        posed = (points[a] - points[b]).length
        ratio = posed / length
        if not math.isfinite(ratio):
            raise ValueError('Non-finite deformed hand edge.')
        ratios.append(ratio)
        for name in categories:
            row = data[name]
            row['min_ratio'] = min(row['min_ratio'], ratio)
            if ratio > row['max_ratio']:
                row['max_ratio'] = ratio
                row['worst_edge'] = {'vertices': [a, b], 'rest_mm': length * 1000, 'posed_mm': posed * 1000}
            row['edges_over_2x'] += ratio > 2
            row['edges_over_3x'] += ratio > 3
            row['edges_over_5x'] += ratio > 5
    return data, ratios


expected_frames = sum(int(action['frame_end']) + 1 for action in definition['actions'])
report = {
    'schema': 'px9-native-every-frame-hand-deformation-1',
    'source': str(source), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'hand_patch_sha256': hashlib.sha256(args.patch.read_bytes()).hexdigest(),
    'manifest_sha256': hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
    'audit_script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'comparison': 'Native evaluated revision3 and recovered revision2 weights under the same actual saved action at every integer frame, including frame0 and endpoints.',
    'limitations': 'Edge strain is a diagnostic, not a proof of anatomy, occlusion or collision. Source topology, faceting and all morph coordinates are preserved. Local edge increases are reported separately even when the overall worst strain improves.',
    'expected_frames': expected_frames, 'hand_vertices': len(hand_vertices), 'hand_edges': len(edges),
    'invariants': invariants, 'maximum_nonhand_weight_error': maximum_nonhand_error,
    'maximum_variant_candidate_weight_error': maximum_patch_error,
    'eligibility_issues': eligibility['issues'], 'actions': {}, 'frames': [],
}
local_worse = {}
maximum_seam_position_difference = 0.0
checkpoint = args.report.with_suffix('.inprogress.json')
if checkpoint.is_file():
    saved = json.loads(checkpoint.read_text())
    identity_keys = ('source_sha256', 'hand_patch_sha256', 'manifest_sha256', 'audit_script_sha256')
    if all(saved.get(key) == report[key] for key in identity_keys):
        known = {action['id']: int(action['frame_end']) + 1 for action in definition['actions']}
        covered = saved.get('actions', {})
        valid = all(name in known and row.get('frames') == known[name] for name, row in covered.items())
        valid = valid and len(saved.get('frames', [])) == sum(known[name] for name in covered)
        if valid:
            expected_pairs = {(name, frame) for name in covered for frame in range(known[name])}
            observed_pairs = {(row.get('action'), row.get('frame')) for row in saved.get('frames', [])}
            valid = observed_pairs == expected_pairs
        if valid:
            report['actions'] = covered
            report['frames'] = saved['frames']
            local_worse = saved.get('checkpoint_local_worse', {})
            maximum_seam_position_difference = saved.get('checkpoint_seam_difference_metres', 0.0)
            print('HAND_AUDIT_RESUME', len(report['frames']), 'completed frames with matching frozen hashes', flush=True)
for action in definition['actions']:
    name = action['id']
    if name in report['actions']:
        continue
    rig.animation_data.use_nla = False
    rig.animation_data.action = bpy.data.actions[action['human_action']]
    action_rows = []
    for frame in range(int(action['frame_end']) + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        before = evaluate_positions(baseline, depsgraph)
        after = evaluate_positions(variant, depsgraph)
        old_stats, old_ratios = summarize(before)
        new_stats, new_ratios = summarize(after)
        maximum_seam_position_difference = max(maximum_seam_position_difference,
            max((before[index] - after[index]).length for index in seam_vertices))
        row = {'action': name, 'frame': frame, 'baseline_v2': old_stats, 'candidate_v3': new_stats}
        report['frames'].append(row)
        action_rows.append(row)
        for number, (old, new) in enumerate(zip(old_ratios, new_ratios)):
            if new > 2.5 and new > old * 1.15:
                a, b, length, categories = edges[number]
                key = f'{a}:{b}'
                previous = local_worse.get(key)
                if previous is None or new > previous['candidate_ratio']:
                    local_worse[key] = {'vertices': [a, b], 'action': name, 'frame': frame,
                        'baseline_ratio': old, 'candidate_ratio': new, 'rest_mm': length * 1000,
                        'categories': categories}
    report['actions'][name] = {
        'frames': len(action_rows),
        'baseline_max_ratio': max(row['baseline_v2']['all_hand']['max_ratio'] for row in action_rows),
        'candidate_max_ratio': max(row['candidate_v3']['all_hand']['max_ratio'] for row in action_rows),
        'candidate_worst_frame': max(action_rows, key=lambda row: row['candidate_v3']['all_hand']['max_ratio'])['frame'],
    }
    print('HAND_FRAMES', name, len(action_rows), report['actions'][name]['candidate_max_ratio'], flush=True)
    report['checkpoint_local_worse'] = local_worse
    report['checkpoint_seam_difference_metres'] = maximum_seam_position_difference
    report['checkpoint_frames_checked'] = len(report['frames'])
    checkpoint.parent.mkdir(parents=True, exist_ok=True)
    temporary = checkpoint.with_suffix('.tmp')
    temporary.write_text(json.dumps(report, indent=2) + '\n')
    temporary.replace(checkpoint)
invariants['original_body_unchanged_after_audit'] = original == deep_record(body) and original_weights == weights(body)
invariants['seam741_742_640_deformation_identical_to_v2'] = maximum_seam_position_difference <= 1e-7
report['frames_checked'] = len(report['frames'])
report['maximum_seam_position_difference_metres'] = maximum_seam_position_difference
report['local_edge_increases_over_2_5x_and_15_percent'] = sorted(local_worse.values(), key=lambda row: row['candidate_ratio'], reverse=True)
report['overall_worst_edge_not_increased_on_any_frame'] = all(
    row['candidate_v3']['all_hand']['max_ratio'] <= row['baseline_v2']['all_hand']['max_ratio'] + 1e-4
    for row in report['frames'])
report['complete_and_invariants_passed'] = len(report['frames']) == expected_frames and all(invariants.values())
for key in ('checkpoint_local_worse', 'checkpoint_seam_difference_metres', 'checkpoint_frames_checked'):
    report.pop(key, None)
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'complete_and_invariants_passed': report['complete_and_invariants_passed'],
                  'frames_checked': report['frames_checked'], 'invariants': invariants,
                  'overall_worst_edge_not_increased_on_any_frame': report['overall_worst_edge_not_increased_on_any_frame'],
                  'local_increased_edges': report['local_edge_increases_over_2_5x_and_15_percent']}, indent=2), flush=True)
if not report['complete_and_invariants_passed']:
    raise SystemExit(2)
if checkpoint.is_file():
    checkpoint.unlink()
