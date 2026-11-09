# SPDX-License-Identifier: CC0-1.0
"""Read-only saved-Action thumb and palm-web strain diagnostic, revision6 to7.

Run with Blender --background CANDIDATE/source/Human.px9_eclipse.blend
--python THIS_SCRIPT -- --baseline BASELINE --candidate CANDIDATE --report PATH.
Uses native bpy and the Python standard library. This does not modify weights,
geometry, animation keys, rig rest data or the source file.

The same accepted skin is evaluated under both saved Rack Actions at all73
inclusive authored frames. Edges incident to any thumb-influenced vertex in
the original or accepted variant are included, including the adjacent palm
web. Edge strain is diagnostic and does not certify anatomy or collision.
"""
from array import array
from pathlib import Path
import argparse
import hashlib
import json
import math
import sys

import bpy


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def weights(obj):
    names = {group.index: group.name for group in obj.vertex_groups}
    return [{names[group.group]: float(group.weight) for group in vertex.groups if group.weight > 0}
            for vertex in obj.data.vertices]


def position_hash(obj):
    values = array('f', [0.0]) * (len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get('co', values)
    return hashlib.sha256(values.tobytes()).hexdigest()


def row_summary(rows):
    ratios = [row['ratio'] for row in rows]
    return {
        'edge_count': len(rows),
        'minimum_ratio': min(ratios), 'maximum_ratio': max(ratios),
        'rms_fractional_strain': math.sqrt(math.fsum((value - 1) ** 2 for value in ratios) / len(ratios)),
        'most_compressed': min(rows, key=lambda row: row['ratio']),
        'most_stretched': max(rows, key=lambda row: row['ratio']),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    baseline, candidate = args.baseline.resolve(), args.candidate.resolve()
    source = candidate / 'source/Human.px9_eclipse.blend'
    if Path(bpy.data.filepath).resolve() != source:
        raise RuntimeError('Open the exact final candidate source for this audit.')
    files = {
        'candidate_source': source,
        'baseline_source': baseline / 'source/Human.px9_eclipse.blend',
        'candidate_patch': candidate / 'source/hand_weight_patch.json',
        'baseline_patch': baseline / 'source/hand_weight_patch.json',
        'candidate_definition': candidate / 'item_px9.json',
        'baseline_definition': baseline / 'item_px9.json',
        'audit_script': Path(__file__),
    }
    identities = {name: sha(path) for name, path in files.items()}
    checks = {
        'accepted_skin_patch_byte_identical': identities['candidate_patch'] == identities['baseline_patch'],
        'item_definition_byte_identical': identities['candidate_definition'] == identities['baseline_definition'],
    }
    if not all(checks.values()):
        raise RuntimeError('This diagnostic requires the same accepted skin and action definitions.')
    scene = bpy.context.scene
    rig = bpy.data.objects['Human_Rig']
    original = bpy.data.objects['Human_Body']
    variant = bpy.data.objects['Human_FP_Hands']
    original_positions = position_hash(original)
    checks['variant_rest_vertex_coordinates_identical'] = position_hash(variant) == original_positions
    checks['variant_vertex_count_identical'] = len(variant.data.vertices) == len(original.data.vertices)
    original_weights, variant_weights = weights(original), weights(variant)
    expected_weights = [dict(row) for row in original_weights]
    patch = json.loads(files['candidate_patch'].read_text())
    for row in patch['vertices']:
        expected_weights[row['vertex']] = {part['bone']: float(part['weight']) for part in row['weights']}
    weight_error = max(abs(actual.get(name, 0) - expected.get(name, 0))
                       for actual, expected in zip(variant_weights, expected_weights)
                       for name in actual.keys() | expected.keys())
    checks['saved_variant_matches_accepted_patch_under_1e7'] = weight_error < 1e-7
    if variant.data.shape_keys:
        checks['neutral_shape_values'] = all(abs(key.value) < 1e-7 for key in variant.data.shape_keys.key_blocks)
    if not all(checks.values()):
        raise RuntimeError('Saved skin invariants failed before deformation sampling: ' + str(checks))
    thumb_mass = lambda row: sum(value for name, value in row.items() if name.startswith('LeftHandThumb'))
    selected = {index for index, (original_row, variant_row) in enumerate(zip(original_weights, variant_weights))
                if max(thumb_mass(original_row), thumb_mass(variant_row)) > 1e-6}
    dominant = {index for index, row in enumerate(variant_weights) if thumb_mass(row) >= .5}
    rest = [original.matrix_world @ vertex.co for vertex in original.data.vertices]
    edges, skipped = [], []
    for edge in original.data.edges:
        a, b = edge.vertices
        if a not in selected and b not in selected:
            continue
        distance = (rest[a] - rest[b]).length
        if distance <= 1e-7:
            skipped.append([a, b])
            continue
        edges.append({'vertices': [a, b], 'rest_length_metres': distance,
                      'region': 'thumb_core' if a in dominant and b in dominant else 'web_and_boundary'})
    if not edges or not any(edge['region'] == 'web_and_boundary' for edge in edges):
        raise RuntimeError('Thumb/palm-web region selection unexpectedly empty.')
    action_name = 'FP_PX9_ECLIPSE_Rack'
    current_action = bpy.data.actions[action_name]
    if files['baseline_source'].resolve() == source:
        # Blender cannot safely append a datablock from its currently open file.
        # This path only serves a diagnostic self-comparison, never a release.
        previous_action = current_action.copy()
    else:
        with bpy.data.libraries.load(str(files['baseline_source']), link=False) as (available, loaded):
            if action_name not in available.actions:
                raise RuntimeError('Baseline saved Rack Action missing.')
            loaded.actions = [action_name]
        previous_action = loaded.actions[0]
    rig.animation_data_create()
    rig.animation_data.use_nla = False
    variant.hide_set(False)

    def sample(action, frame):
        rig.animation_data.action = action
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        deps = bpy.context.evaluated_depsgraph_get()
        evaluated = variant.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        try:
            if len(mesh.vertices) != len(original.data.vertices):
                raise RuntimeError('Evaluated mesh changed topology or vertex ordering.')
            points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
            return [{'vertices': edge['vertices'], 'region': edge['region'],
                     'rest_length_metres': edge['rest_length_metres'],
                     'deformed_length_metres': (points[edge['vertices'][0]] - points[edge['vertices'][1]]).length,
                     'ratio': (points[edge['vertices'][0]] - points[edge['vertices'][1]]).length / edge['rest_length_metres']}
                    for edge in edges]
        finally:
            evaluated.to_mesh_clear()

    frames, comparisons = [], []
    for frame in range(73):
        old, new = sample(previous_action, frame), sample(current_action, frame)
        row = {'frame': frame, 'seconds': frame / 60, 'baseline': {}, 'candidate': {}}
        for region in ('all', 'thumb_core', 'web_and_boundary'):
            old_region = [edge for edge in old if region == 'all' or edge['region'] == region]
            new_region = [edge for edge in new if region == 'all' or edge['region'] == region]
            row['baseline'][region] = row_summary(old_region)
            row['candidate'][region] = row_summary(new_region)
        differences = [{'vertices': a['vertices'], 'region': a['region'],
                        'rest_length_metres': a['rest_length_metres'],
                        'baseline_length_metres': a['deformed_length_metres'],
                        'candidate_length_metres': b['deformed_length_metres'],
                        'length_increase_metres': b['deformed_length_metres'] - a['deformed_length_metres'],
                        'baseline_ratio': a['ratio'], 'candidate_ratio': b['ratio'],
                        'absolute_strain_increase': abs(b['ratio'] - 1) - abs(a['ratio'] - 1)}
                       for a, b in zip(old, new)]
        row['largest_strain_increases'] = sorted(differences, key=lambda edge: edge['absolute_strain_increase'], reverse=True)[:8]
        row['edges_with_absolute_strain_increase_over_point1'] = sum(edge['absolute_strain_increase'] > .1 for edge in differences)
        comparisons.extend({'frame': frame, **edge} for edge in differences)
        frames.append(row)
    checks.update({
        'all73_authored_frames_sampled': len(frames) == 73,
        'all_measurements_finite': all(math.isfinite(value)
            for row in comparisons for key, value in row.items() if key.endswith('ratio') or key == 'absolute_strain_increase'),
        'original_mesh_coordinates_unchanged_in_memory': position_hash(original) == original_positions,
        'all_input_files_unchanged': identities == {name: sha(path) for name, path in files.items()},
    })
    report = {
        'schema': 'px9-rack-thumb-saved-skin-strain-revision7-1',
        'passed': all(checks.values()),
        'pass_definition': 'Complete finite diagnostics on all73 saved-action frames and exact input/skin invariants. Strain figures and anatomy require separate visual review; passing does not assert improvement of every edge.',
        'checks': checks, 'inputs': identities, 'input_paths': {name: str(path) for name, path in files.items()},
        'skin_patch_revision': patch.get('patch_revision'), 'maximum_saved_variant_patch_error': weight_error,
        'vertex_selection': 'Union of original or accepted skin vertices with any left-thumb weight >1e-6; all source edges incident to these vertices. Core requires both endpoints to have >=0.5 accepted thumb influence. Remaining incident edges include the adjacent web and boundary.',
        'selected_thumb_vertices': len(selected), 'tested_edges': len(edges),
        'core_edges': sum(edge['region'] == 'thumb_core' for edge in edges),
        'web_and_boundary_edges': sum(edge['region'] == 'web_and_boundary' for edge in edges),
        'skipped_zero_length_source_edges': skipped,
        'frame_count': len(frames), 'frames': frames,
        'largest_strain_increases': sorted(comparisons, key=lambda edge: edge['absolute_strain_increase'], reverse=True)[:30],
        'largest_absolute_length_increases': sorted(comparisons, key=lambda edge: edge['length_increase_metres'], reverse=True)[:30],
        'baseline_overall_minimum_ratio': min(row['baseline_ratio'] for row in comparisons),
        'baseline_overall_maximum_ratio': max(row['baseline_ratio'] for row in comparisons),
        'candidate_overall_minimum_ratio': min(row['candidate_ratio'] for row in comparisons),
        'candidate_overall_maximum_ratio': max(row['candidate_ratio'] for row in comparisons),
        'limitations': 'Evaluated source edge lengths are not surface-collision distances, medical/anatomical limits, pressure measurements, or proof of visual quality. Unchanged mesh faceting persists. Interframes are covered by the separate exported/native wrist-thumb path audit.',
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key not in ('frames', 'largest_strain_increases')}, indent=2), flush=True)
    print('FRAME031', json.dumps(frames[31], indent=2), flush=True)
    if not report['passed']:
        raise RuntimeError('Saved thumb deformation input/coverage invariants failed.')


if __name__ == '__main__':
    main()
