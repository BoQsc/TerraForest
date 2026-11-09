# SPDX-License-Identifier: CC0-1.0
"""Compare previous/current PX9 hand deformation at every authored frame.

Open the candidate source with native Blender, then pass:
  --baseline PREVIOUS_PACKAGE --candidate CURRENT_PACKAGE --report REPORT.json

The previous patch is applied to a private copy of the untouched Human_Body.
Only the previous package's 20 FP Actions are appended. The previous skin and
actions are compared with the candidate's saved skin and actions. Measurements
cover the complete right-hand region, its adjacent wrist boundary, and all
reviewed right-side patch vertices. Original and both variant skin memberships
are included. No source file is saved.
"""
from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import sys
import time

import bpy


def sha(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def weights(obj):
    return [{obj.vertex_groups[group.group].name: float(group.weight)
             for group in vertex.groups if group.weight > 0.0}
            for vertex in obj.data.vertices]


def position_hash(obj):
    values = array('f', [0.0]) * (len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get('co', values)
    return hashlib.sha256(values.tobytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    baseline, candidate = args.baseline.resolve(), args.candidate.resolve()
    source = candidate / 'source/Human.px9_eclipse.blend'
    if Path(bpy.data.filepath).resolve() != source:
        raise ValueError('Open the exact candidate source before running this audit.')
    started = time.monotonic()
    identities = {name: sha(path) for name, path in {
        'baseline_source_sha256': baseline / 'source/Human.px9_eclipse.blend',
        'candidate_source_sha256': source,
        'baseline_patch_sha256': baseline / 'source/hand_weight_patch.json',
        'candidate_patch_sha256': candidate / 'source/hand_weight_patch.json',
        'baseline_definition_sha256': baseline / 'item_px9.json',
        'candidate_definition_sha256': candidate / 'item_px9.json',
        'audit_script_sha256': Path(__file__),
    }.items()}
    definition = json.loads((candidate / 'item_px9.json').read_text())
    prior_definition = json.loads((baseline / 'item_px9.json').read_text())
    if definition['actions'] != prior_definition['actions'] or definition['fps'] != 60:
        raise ValueError('Paired clip/timing contract changed.')
    patch = json.loads((candidate / 'source/hand_weight_patch.json').read_text())
    prior_patch = json.loads((baseline / 'source/hand_weight_patch.json').read_text())
    sys.path.insert(0, str(candidate / 'source'))
    from human_hand_weights import apply_hand_patch

    scene = bpy.context.scene
    rig = bpy.data.objects['Human_Rig']
    original = bpy.data.objects['Human_Body']
    variant = bpy.data.objects['Human_FP_Hands']
    original_position_hash = position_hash(original)
    original_weight_rows = weights(original)
    current_actions = {row['id']: bpy.data.actions[row['human_action']]
                       for row in definition['actions']}
    names = [row['human_action'] for row in definition['actions']]
    with bpy.data.libraries.load(str(baseline / 'source/Human.px9_eclipse.blend'), link=False) as (available, loaded):
        if not all(name in available.actions for name in names):
            raise ValueError('A previous FP Action is missing.')
        loaded.actions = names
    old_actions = dict(zip((row['id'] for row in definition['actions']), loaded.actions))
    if any(action is None for action in old_actions.values()):
        raise ValueError('A previous FP Action failed to append.')
    old_variant = original.copy()
    old_variant.data = original.data.copy()
    old_variant.name = 'AuditOnly_PreviousHandVariant'
    scene.collection.objects.link(old_variant)
    old_variant.hide_set(False)
    old_variant.hide_render = True
    apply_hand_patch(old_variant, rig, prior_patch)
    for obj in (old_variant, variant):
        if any(abs(block.value) > 1e-7 for block in obj.data.shape_keys.key_blocks):
            raise ValueError('Hand deformation audit expects neutral item shape values.')
    old_weights, new_weights = weights(old_variant), weights(variant)
    expected_new_weights = [dict(row) for row in original_weight_rows]
    for row in patch['vertices']:
        expected_new_weights[row['vertex']] = {part['bone']: float(part['weight']) for part in row['weights']}
    maximum_candidate_patch_error = max(
        (abs(actual.get(name, 0.0) - expected.get(name, 0.0))
         for actual, expected in zip(new_weights, expected_new_weights)
         for name in actual.keys() | expected.keys()), default=0.0)
    if maximum_candidate_patch_error > 1e-7:
        raise ValueError('Saved candidate variant does not match its supplied patch; build before auditing.')
    changed_weight_vertices = {
        index for index, (old, new) in enumerate(zip(old_weights, new_weights))
        if max((abs(old.get(name, 0.0) - new.get(name, 0.0))
                for name in old.keys() | new.keys()), default=0.0) > 1e-7}
    hand_finger_bones = {f'RightHand{finger}{joint}'
                         for finger in ('Index', 'Middle', 'Ring', 'Pinky', 'Thumb') for joint in (1, 2, 3)}
    memberships = list(zip(original_weight_rows, old_weights, new_weights))
    affected = {index for index, versions in enumerate(memberships)
                if any(sum(value for name, value in row.items() if name.startswith('RightHand')) > .45
                       or any(row.get(name, 0.0) > 0.0 for name in hand_finger_bones)
                       for row in versions)}
    affected.update(row['vertex'] for candidate_patch in (prior_patch, patch)
                    for row in candidate_patch['vertices'] if row['side'] == 'Right')
    affected.update(changed_weight_vertices)
    web = {444, 479}
    seam = {640, 741, 742}
    palm = {row['vertex'] for row in patch['vertices'] if row['finger'] == 'Palm'}
    rest = [original.matrix_world @ vertex.co for vertex in original.data.vertices]
    edges = []
    family_vertices = {
        finger: {index for index, (old, new) in enumerate(zip(old_weights, new_weights))
                 if any(old.get(f'RightHand{finger}{joint}', 0.0) > 0.0 or
                        new.get(f'RightHand{finger}{joint}', 0.0) > 0.0 for joint in (1, 2, 3))}
        for finger in ('Index', 'Middle', 'Ring', 'Pinky', 'Thumb')}
    for edge in original.data.edges:
        a, b = edge.vertices
        if a not in affected and b not in affected and a not in web and b not in web:
            continue
        length = (rest[a] - rest[b]).length
        if length <= 1e-9:
            continue
        categories = ['affected_region']
        if a in web or b in web:
            categories.append('proximal_index_middle_web')
        if a in palm or b in palm:
            categories.append('central_palm')
        if a in seam or b in seam:
            categories.append('source_seam741')
        for finger, vertices in family_vertices.items():
            if a in vertices or b in vertices:
                categories.append(finger.lower())
        if a in changed_weight_vertices or b in changed_weight_vertices:
            categories.append('reassigned_tip_ownership')
        edges.append((a, b, length, categories))
    categories = sorted({category for *_, names in edges for category in names})
    region = sorted({index for a, b, *_ in edges for index in (a, b)})

    def positions(obj):
        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        points = {index: obj.matrix_world @ mesh.vertices[index].co for index in region}
        evaluated.to_mesh_clear()
        return points

    def summarize(points):
        summary = {name: {'maximum_ratio': 0.0, 'minimum_ratio': float('inf'),
                          'edges_over_2x': 0, 'edges_over_3x': 0, 'edges_over_5x': 0,
                          'worst_edge': None} for name in categories}
        ratios = []
        for a, b, length, names in edges:
            posed = (points[a] - points[b]).length
            ratio = posed / length
            if not math.isfinite(ratio):
                raise ValueError('Non-finite evaluated hand edge.')
            ratios.append(ratio)
            for name in names:
                row = summary[name]
                row['minimum_ratio'] = min(row['minimum_ratio'], ratio)
                if ratio > row['maximum_ratio']:
                    row['maximum_ratio'] = ratio
                    row['worst_edge'] = {'vertices': [a, b], 'rest_mm': length * 1000,
                                         'posed_mm': posed * 1000}
                row['edges_over_2x'] += ratio > 2
                row['edges_over_3x'] += ratio > 3
                row['edges_over_5x'] += ratio > 5
        return summary, ratios

    expected = sum(row['frame_end'] + 1 for row in definition['actions'])
    report = {
        'schema': 'px9-grip-revision-deformation-1',
        'baseline': str(baseline), 'candidate': str(candidate), **identities,
        'scope': 'Native evaluation of the previous saved FP Actions with the previous skin patch against the final saved FP Actions and skin variant. All inclusive authored frames are sampled. Source edges touching the entire right-hand membership union, the adjacent wrist boundary, or reviewed right-side patch rows are measured, including the proximal index/middle web and source seam741.',
        'region_selection': 'Union of original, previous-variant and final-variant vertices with >45% RightHand-prefix mass or any positive right-finger influence, plus every right-side row in either hand patch. Edges include neighboring vertices outside that membership, so retained forearm influences at the hand/wrist boundary are measured.',
        'limitations': 'Edge strain measures mesh stretch, not anatomical correctness, surface collision, fingertip contact, or perceived quality. Individual edges may increase even when the overall maximum falls. Other hand/body edges are outside this focused report; source preservation is checked separately.',
        'baseline_patch_revision': prior_patch.get('patch_revision'),
        'candidate_patch_revision': patch.get('patch_revision'),
        'maximum_candidate_patch_weight_error': maximum_candidate_patch_error,
        'changed_weight_vertices': sorted(changed_weight_vertices),
        'affected_weighted_vertices': len(affected), 'measured_vertices_including_neighbors': len(region),
        'measured_edges': len(edges), 'category_edge_counts': {
            name: sum(name in row[3] for row in edges) for name in categories},
        'expected_frame_samples': expected, 'clips': {}, 'frames': [],
        'invariants': {
            'baseline_and_candidate_actions_are_separate_datablocks': all(
                old_actions[name] != current_actions[name] for name in current_actions),
            'same_source_positions': position_hash(old_variant) == position_hash(variant) == original_position_hash,
            'same_mesh_edges': [tuple(e.vertices) for e in old_variant.data.edges] ==
                               [tuple(e.vertices) for e in variant.data.edges],
            'same_rig_for_both_variants': all(
                any(mod.type == 'ARMATURE' and mod.object == rig for mod in obj.modifiers)
                for obj in (old_variant, variant)),
        },
    }
    local_increases = {}
    checkpoint = args.report.with_suffix('.inprogress.json')
    if checkpoint.is_file():
        saved = json.loads(checkpoint.read_text())
        if all(saved.get(key) == value for key, value in identities.items()):
            valid_clips = {row['id']: row['frame_end'] + 1 for row in definition['actions']}
            completed = saved.get('clips', {})
            expected_pairs = {(name, frame) for name in completed for frame in range(valid_clips[name])}
            observed_pairs = {(row['action'], row['frame']) for row in saved.get('frames', [])}
            if expected_pairs == observed_pairs and len(observed_pairs) == len(saved.get('frames', [])):
                report['clips'] = completed
                report['frames'] = saved['frames']
                local_increases = saved.get('local_increase_checkpoint', {})
                print('GRIP_DEFORMATION_RESUME', len(report['frames']), flush=True)
    for action in definition['actions']:
        name, end = action['id'], action['frame_end']
        if name in report['clips']:
            continue
        clip_start = time.monotonic()
        rig.animation_data.use_nla = False
        rig.animation_data.action = old_actions[name]
        previous_rows = []
        for frame in range(end + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            previous_rows.append(summarize(positions(old_variant)))
        rig.animation_data.action = current_actions[name]
        clip_rows = []
        for frame in range(end + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            current, current_ratios = summarize(positions(variant))
            previous, previous_ratios = previous_rows[frame]
            row = {'action': name, 'frame': frame, 'baseline': previous, 'candidate': current}
            report['frames'].append(row)
            clip_rows.append(row)
            for index, (old, new) in enumerate(zip(previous_ratios, current_ratios)):
                if new > 2.5 and new > old * 1.15:
                    a, b, length, names = edges[index]
                    key = f'{a}:{b}'
                    earlier = local_increases.get(key)
                    if earlier is None or new > earlier['candidate_ratio']:
                        local_increases[key] = {'vertices': [a, b], 'action': name, 'frame': frame,
                            'baseline_ratio': old, 'candidate_ratio': new, 'rest_mm': length * 1000,
                            'baseline_length_mm': old * length * 1000,
                            'candidate_length_mm': new * length * 1000, 'categories': names}
        report['clips'][name] = {
            'frames': len(clip_rows), 'elapsed_seconds': round(time.monotonic() - clip_start, 3),
            'baseline_maximum_ratio': max(row['baseline']['affected_region']['maximum_ratio'] for row in clip_rows),
            'candidate_maximum_ratio': max(row['candidate']['affected_region']['maximum_ratio'] for row in clip_rows),
            'candidate_worst_frame': max(clip_rows, key=lambda row: row['candidate']['affected_region']['maximum_ratio'])['frame'],
        }
        report['local_increase_checkpoint'] = local_increases
        write_json(checkpoint, report)
        print('GRIP_DEFORMATION_CLIP', name, json.dumps(report['clips'][name]), flush=True)
    report['invariants']['original_source_positions_unchanged_in_memory'] = position_hash(original) == original_position_hash
    report['invariants']['original_source_weights_unchanged_in_memory'] = weights(original) == original_weight_rows
    report['invariants']['candidate_source_file_unmodified'] = sha(source) == identities['candidate_source_sha256']
    report['invariants']['baseline_source_file_unmodified'] = sha(baseline / 'source/Human.px9_eclipse.blend') == identities['baseline_source_sha256']
    report['frames_checked'] = len(report['frames'])
    report['elapsed_seconds'] = round(time.monotonic() - started, 3)
    report['local_edge_increases_over_2_5x_and_15_percent'] = sorted(
        local_increases.values(), key=lambda row: row['candidate_ratio'], reverse=True)
    report['maxima_by_category'] = {
        name: {label: max(report['frames'], key=lambda row: row[label][name]['maximum_ratio'])
               for label in ('baseline', 'candidate')} for name in categories}
    report['overall_worst_edge_not_increased_on_any_frame'] = all(
        row['candidate']['affected_region']['maximum_ratio'] <=
        row['baseline']['affected_region']['maximum_ratio'] + 1e-4 for row in report['frames'])
    report['complete_and_invariants_passed'] = len(report['frames']) == expected and all(report['invariants'].values())
    report.pop('local_increase_checkpoint', None)
    write_json(args.report, report)
    if checkpoint.is_file():
        checkpoint.unlink()
    print(json.dumps({key: value for key, value in report.items() if key not in ('frames', 'maxima_by_category')}, indent=2), flush=True)
    if not report['complete_and_invariants_passed']:
        raise SystemExit(2)


if __name__ == '__main__':
    main()
