# SPDX-License-Identifier: CC0-1.0
"""Targeted binary checks for paired first-person GLBs (stdlib only).

This is a schema/clip/rig/texture-contract audit, not full Khronos validation.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import struct

COMPONENTS = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2),
              5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4,
          'MAT2': 4, 'MAT3': 9, 'MAT4': 16}


class Glb:
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        magic, version, declared = struct.unpack_from('<III', self.data)
        if magic != 0x46546C67 or version != 2 or declared != len(self.data):
            raise ValueError('Invalid GLB header: ' + str(path))
        offset = 12
        chunks = {}
        while offset < len(self.data):
            length, kind = struct.unpack_from('<II', self.data, offset)
            offset += 8
            if length % 4 or offset + length > len(self.data):
                raise ValueError('Invalid GLB chunk')
            chunks[kind] = self.data[offset:offset + length]
            offset += length
        self.doc = json.loads(chunks[0x4E4F534A])
        self.binary = chunks.get(0x004E4942, b'')
        self.cache = {}

    def accessor(self, index):
        if index in self.cache:
            return self.cache[index]
        info = self.doc['accessors'][index]
        if info.get('sparse'):
            raise ValueError('Sparse accessor is outside this export contract')
        component, component_size = COMPONENTS[info['componentType']]
        width = WIDTHS[info['type']]
        count = info['count']
        if 'bufferView' not in info:
            values = [(0,) * width for _ in range(count)]
        else:
            view = self.doc['bufferViews'][info['bufferView']]
            if view.get('buffer', 0) != 0:
                raise ValueError('External buffer is outside this export contract')
            view_start = view.get('byteOffset', 0)
            start = view_start + info.get('byteOffset', 0)
            stride = view.get('byteStride', width * component_size)
            end = start + (count - 1) * stride + width * component_size if count else start
            if end > view_start + view['byteLength'] or end > len(self.binary):
                raise ValueError('Accessor exceeds buffer range')
            values = [struct.unpack_from('<' + component * width, self.binary, start + row * stride)
                      for row in range(count)]
        if info.get('normalized'):
            if info['componentType'] == 5121:
                values = [tuple(value / 255 for value in row) for row in values]
            elif info['componentType'] == 5123:
                values = [tuple(value / 65535 for value in row) for row in values]
            elif info['componentType'] == 5120:
                values = [tuple(max(-1, value / 127) for value in row) for row in values]
            elif info['componentType'] == 5122:
                values = [tuple(max(-1, value / 32767) for value in row) for row in values]
        self.cache[index] = values
        return values

    def image_hashes(self):
        records = []
        for image in self.doc.get('images', []):
            if 'bufferView' not in image:
                raise ValueError('Runtime image is not embedded')
            view = self.doc['bufferViews'][image['bufferView']]
            start = view.get('byteOffset', 0)
            payload = self.binary[start:start + view['byteLength']]
            records.append({'name': image.get('name'), 'bytes': len(payload),
                            'sha256': hashlib.sha256(payload).hexdigest()})
        return records


def audit_file(glb, rows, role, human_reference, weapon_reference):
    errors = []
    checks = {}

    def check(name, condition, detail=None):
        checks[name] = bool(condition)
        if not condition:
            errors.append({'check': name, 'detail': detail})

    doc = glb.doc
    nodes = doc.get('nodes', [])
    skins = doc.get('skins', [])
    animations = {animation.get('name', ''): animation for animation in doc.get('animations', [])}
    key = 'human_clip' if role == 'human' else 'item_clip'
    expected = {row[key]: row for row in rows}
    check('unique_animation_names', len(animations) == len(doc.get('animations', [])))
    check('twenty_expected_first_person_clips', len(expected) == 20 and set(expected).issubset(animations), sorted(set(expected) - animations.keys()))
    if role == 'human':
        check('only_new_first_person_clips', set(animations) == set(expected), sorted(animations.keys() - expected.keys()))
    else:
        original_clip_names = {'assemble', 'disassemble', 'draw', 'fire', 'fire_last_round', 'holster',
                              'idle', 'inspect', 'rack_slide', 'reload_empty', 'reload_tactical'}
        check('original_eleven_weapon_clips_preserved', original_clip_names.issubset(animations), sorted(original_clip_names - animations.keys()))
    check('one_skin', len(skins) == 1, len(skins))
    joint_nodes = set(skins[0]['joints']) if len(skins) == 1 else set()
    joint_names = [nodes[index].get('name', '') for index in joint_nodes]
    reference = human_reference if role == 'human' else weapon_reference
    check('exact_joint_names_and_count', len(joint_nodes) == (59 if role == 'human' else 22)
          and set(joint_names) == set(reference['bones']), joint_names)
    parents = {}
    for index, node in enumerate(nodes):
        for child in node.get('children', []):
            if child in parents:
                errors.append({'check': 'single_node_parent', 'detail': child})
            parents[child] = index
    changed_parents = []
    for index in joint_nodes:
        name = nodes[index].get('name')
        parent = parents.get(index)
        actual = nodes[parent].get('name') if parent in joint_nodes else None
        if name in reference['bones'] and actual != reference['bones'][name]['parent']:
            changed_parents.append({'bone': name, 'actual': actual, 'expected': reference['bones'][name]['parent']})
    check('joint_parents_preserved', not changed_parents, changed_parents)

    mesh_nodes = [node for node in nodes if 'mesh' in node]
    skinned_nodes = [node for node in mesh_nodes if 'skin' in node]
    triangles = 0
    vertices = 0
    bad_influences = []
    mesh_names = []
    for node in mesh_nodes:
        mesh_names.append(node.get('name'))
        mesh = doc['meshes'][node['mesh']]
        for primitive in mesh['primitives']:
            check('triangles_primitive_mode_' + str(node.get('name')), primitive.get('mode', 4) == 4)
            vertex_count = doc['accessors'][primitive['attributes']['POSITION']]['count']
            indices = glb.accessor(primitive['indices']) if 'indices' in primitive else [(i,) for i in range(vertex_count)]
            if len(indices) % 3:
                errors.append({'check': 'triangle_index_multiple', 'detail': node.get('name')})
            triangles += len(indices) // 3
            vertices += vertex_count
            if role == 'weapon':
                weights = glb.accessor(primitive['attributes']['WEIGHTS_0'])
                joints = glb.accessor(primitive['attributes']['JOINTS_0'])
                for i, (weight_row, joint_row) in enumerate(zip(weights, joints)):
                    active = [(joint, weight) for joint, weight in zip(joint_row, weight_row) if weight > 1e-7]
                    if len(active) != 1 or abs(active[0][1] - 1.0) > 1e-6 or not 0 <= active[0][0] < len(joint_nodes):
                        bad_influences.append([node.get('name'), i])
    if role == 'human':
        check('animation_carrier_without_material_images', not doc.get('materials') and not doc.get('images') and not doc.get('textures'))
    else:
        check('seventeen_separate_skinned_meshes', len(mesh_nodes) == len(skinned_nodes) == len(doc.get('meshes', [])) == 17,
              {'mesh_nodes': len(mesh_nodes), 'skinned_nodes': len(skinned_nodes), 'mesh_data': len(doc.get('meshes', []))})
        check('weapon_mesh_names_preserved', set(mesh_names) == set(reference['meshes']), mesh_names)
        check('weapon_19616_triangles_under_20000', triangles == 19616 and triangles < 20000, triangles)
        check('weapon_rigid_unit_influences', not bad_influences, bad_influences[:20])
        check('one_material_three_embedded_images', len(doc.get('materials', [])) == 1 and len(doc.get('images', [])) == 3)
    image_records = glb.image_hashes()
    if role == 'weapon':
        expected_image_hashes = {weapon_reference['images'][name]['packed_sha256'] for name in
                                 ['PX9_Skeleton_BaseColor', 'PX9_Skeleton_Normal', 'PX9_Skeleton_ORM']}
        check('original_runtime_pbr_bytes_preserved', {row['sha256'] for row in image_records} == expected_image_hashes, image_records)
        material = doc.get('materials', [{}])[0]
        metallic_roughness = material.get('pbrMetallicRoughness', {})
        pbr_routes = []
        for usage, texture_info, source_name in [
            ('base_color', metallic_roughness.get('baseColorTexture'), 'PX9_Skeleton_BaseColor'),
            ('normal', material.get('normalTexture'), 'PX9_Skeleton_Normal'),
            ('metallic_roughness', metallic_roughness.get('metallicRoughnessTexture'), 'PX9_Skeleton_ORM'),
            ('occlusion', material.get('occlusionTexture'), 'PX9_Skeleton_ORM'),
        ]:
            actual_hash = None
            try:
                source_index = doc['textures'][texture_info['index']]['source']
                actual_hash = image_records[source_index]['sha256']
            except (KeyError, IndexError, TypeError):
                pass
            expected_hash = weapon_reference['images'][source_name]['packed_sha256']
            pbr_routes.append({'usage': usage, 'expected_image': source_name,
                               'actual_image_sha256': actual_hash, 'matches': actual_hash == expected_hash})
        check('pbr_base_color_normal_and_orm_connected_correctly', all(route['matches'] for route in pbr_routes), pbr_routes)
        check('pbr_original_opaque_factors_preserved',
              metallic_roughness.get('baseColorFactor', [1, 1, 1, 1]) == [1, 1, 1, 1]
              and metallic_roughness.get('metallicFactor', 1) == 1
              and metallic_roughness.get('roughnessFactor', 1) == 1
              and material.get('normalTexture', {}).get('scale', 1) == 1
              and material.get('occlusionTexture', {}).get('strength', 1) == 1
              and material.get('alphaMode', 'OPAQUE') == 'OPAQUE'
              and 'KHR_materials_unlit' not in material.get('extensions', {}))

    clip_reports = []
    for name, row in expected.items():
        if name not in animations:
            continue
        animation = animations[name]
        frame_end = row['frame_end']
        problems = []
        all_times = []
        channel_counts = []
        channels = []
        for channel in animation.get('channels', []):
            target = channel.get('target', {})
            if target.get('node') not in joint_nodes or target.get('path') not in ['translation', 'rotation', 'scale']:
                problems.append({'type': 'not_joint_trs', 'target': target})
                continue
            sampler = animation['samplers'][channel['sampler']]
            times = [value[0] for value in glb.accessor(sampler['input'])]
            values = glb.accessor(sampler['output'])
            channel_counts.append(len(times))
            all_times.extend(times)
            if not times or any(not math.isfinite(value) for value in times):
                problems.append({'type': 'invalid_times', 'target': target})
                continue
            if any(a >= b for a, b in zip(times, times[1:])):
                problems.append({'type': 'times_not_strictly_increasing', 'target': target})
            if any(abs(time * 60 - round(time * 60)) > 0.0005 for time in times):
                problems.append({'type': 'key_off_60fps_grid', 'target': target})
            if any(not math.isfinite(component) for value in values for component in value):
                problems.append({'type': 'nonfinite_values', 'target': target})
            if sampler.get('interpolation', 'LINEAR') != 'LINEAR':
                problems.append({'type': 'nonlinear_interpolation', 'target': target})
            if len(values) != len(times):
                problems.append({'type': 'value_time_count_mismatch', 'target': target})
            if target['path'] == 'rotation':
                if any(abs(math.sqrt(sum(component * component for component in q)) - 1.0) > 0.001 for q in values):
                    problems.append({'type': 'nonunit_quaternion', 'target': target})
                if any(sum(a * b for a, b in zip(q1, q2)) < -0.000001 for q1, q2 in zip(values, values[1:])):
                    problems.append({'type': 'quaternion_hemisphere_flip', 'target': target})
            if target['path'] == 'scale' and any(min(value) <= 0 for value in values):
                problems.append({'type': 'nonpositive_scale', 'target': target})
            channels.append({'node': nodes[target['node']].get('name'), 'path': target['path'], 'keys': len(times)})
        start = min(all_times) if all_times else None
        end = max(all_times) if all_times else None
        if start is None or abs(start) > 1e-7 or abs(end - frame_end / 60.0) > 1e-5:
            problems.append({'type': 'incorrect_duration', 'actual_range': [start, end], 'expected_end': frame_end / 60.0})
        check('clip_contract_' + row['id'], not problems, problems[:15])
        clip_reports.append({'name': name, 'frame_end': frame_end, 'expected_fps': 60,
                             'time_start': start, 'time_end': end, 'channels': len(channels),
                             'minimum_keys_per_channel': min(channel_counts) if channel_counts else 0,
                             'maximum_keys_per_channel': max(channel_counts) if channel_counts else 0,
                             'problems': problems, 'passed': not problems})
    return {
        'role': role, 'file': glb.path.name, 'bytes': len(glb.data),
        'sha256': hashlib.sha256(glb.data).hexdigest(),
        'passed': not errors, 'errors': errors, 'checks': checks,
        'nodes': len(nodes), 'skins': len(skins), 'joints': len(joint_nodes),
        'mesh_nodes': len(mesh_nodes), 'skinned_mesh_nodes': len(skinned_nodes),
        'triangles': triangles, 'vertices': vertices,
        'animation_count': len(animations), 'animation_names': list(animations),
        'images': image_records, 'first_person_clips': clip_reports,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--definition', type=Path, required=True)
    parser.add_argument('--human', type=Path, required=True)
    parser.add_argument('--weapon', type=Path, required=True)
    parser.add_argument('--reference-human', type=Path, default=Path(__file__).with_name('original_r11_contract.json'))
    parser.add_argument('--reference-weapon', type=Path, default=Path(__file__).with_name('original_px9_contract.json'))
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    definition = json.loads(args.definition.read_text())
    human_reference = json.loads(args.reference_human.read_text())
    weapon_reference = json.loads(args.reference_weapon.read_text())
    results = []
    for role, path in [('human', args.human), ('weapon', args.weapon)]:
        results.append(audit_file(Glb(path), definition['actions'], role, human_reference, weapon_reference))
    report = {'schema': 'px9-first-person-export-contract-1',
              'passed': all(row['passed'] for row in results),
              'definition_file': args.definition.name,
              'definition_sha256': hashlib.sha256(args.definition.read_bytes()).hexdigest(),
              'files': results,
              'scope': 'Targeted GLB/accessor/skin/mesh/texture and twenty-paired-clip timing checks. Source every-frame keys are checked separately; constant channels may be optimized. Not full Khronos conformance or visual-quality approval.'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'files': [
        {'role': row['role'], 'passed': row['passed'], 'triangles': row['triangles'],
         'joints': row['joints'], 'animation_count': row['animation_count'],
         'failed_checks': [name for name, passed in row['checks'].items() if not passed]}
        for row in results], 'report': str(args.report)}, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
