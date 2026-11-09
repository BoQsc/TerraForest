# SPDX-License-Identifier: CC0-1.0
"""Reproduce the reviewed PX9 Human R11 hand-skin revisions 3 through 5.

Only variant weights are authored. This module never modifies mesh data,
vertex groups, UVs, shape keys or the armature. Pass the untouched Human_Body,
Human_Rig and either the frozen revision-2 patch or the supplied revision-3
patch. apply_hand_patch() in human_hand_weights.py applies the returned data
to a separate Human_FP_Hands copy.

Revision 4 retains revision 3 and corrects seven connected Middle-finger
vertices that the nearest-chain rule assigned to Ring. Both prior revisions
remain exactly recoverable from the embedded frozen records.

Revision 5 retains revision 4 and corrects three left Middle shaft/pad
vertices plus one proximal Middle/Ring web vertex. The latter retains a
balanced adjacent-family blend to limit compression in other item clips.
The source left/right hands are asymmetric; the
seven right-hand indices are deliberately not mirrored. Pose revision 6
uses this skin revision 5 while preserving the original Human_Body.

The 269 central-palm rows address remote digit influences outside revision
2's finger capsules. The two explicit proximal web rows are source mesh
junctions, rather than finger shafts; they retain a small adjacent-root
blend. Vertex 741 and its reference neighbor 742 are not revised.
"""
import copy
import hashlib
import json

from human_hand_weights import FAMILIES, _finger_weights, _nearest_chain, _smooth

FROZEN_PATCH_SHA256 = '42b1a15fd864d1f43b691630e41ccf192e6db4894acdb70fb7dec9730f60ab0c'
FROZEN_ROWS_SHA256 = '4e29ea49e1409107ccef77edf9e6b6d1d35011afab37d5adf16a09f095cb47a9'
REVISION_2_PARENT_SHA256 = '7f21b1383a415072bc998f6443b03e440e55c54ce9e8f7098a9c163f7900c714'
METHOD_SUFFIX = ' Additional central-palm stabilization outside the original finger-chain eligibility region.'
REVISION_3_PATCH_SHA256 = '1908ffec446331c66cbb8c43b19c7dc34931e79844d01770d75043724e945e4f'
REVISION_3_ROWS_SHA256 = 'a715fae23e52364faf8ff32683c9bdc7325404f41559cbb5d1f35eea2b85ab0f'
DISTAL_MIDDLE_VERTICES = (3, 9, 109, 118, 121, 123, 125)
DISTAL_METHOD_SUFFIX = ' Seven topology-reviewed right Middle-finger vertices retain Middle-chain ownership instead of nearest Ring-chain ownership.'
REVISION_4_PATCH_SHA256 = '7f7165d208ced4a8d4259b990d6ffcc8503ba3170f6e382e9dc2654565e68ab3'
REVISION_4_ROWS_SHA256 = '62679ff9e126059fded01b82650ad607360903a61fcd02898277c12b5ec513e0'
LEFT_DISTAL_MIDDLE_VERTICES = (4578, 4597, 4633, 4637)
LEFT_DISTAL_PURE_TRIAL_SUFFIX = ' Four topology-reviewed left Middle-finger vertices retain Middle-chain ownership instead of nearest Ring-chain ownership.'
LEFT_DISTAL_METHOD_SUFFIX = ' Three topology-reviewed left Middle shaft/pad vertices retain Middle-chain ownership; proximal web vertex 4597 blends the Middle and previous Ring chains equally.'
LEFT_MIDDLE_RING_WEB = {'vertex': 4597, 'middle_chain_fraction': .5, 'previous_ring_chain_fraction': .5}
PALM_SPEC = {
    'minimum_original_same_hand_weight_sum': .5,
    'hand_rest_local_x_range_metres': [-.052, .052],
    'hand_rest_local_y_range_metres': [.025, .110],
    'hand_rest_local_z_range_metres': [-.035, .030],
    'excluded_preserved_vertices': [741, 742],
    'must_be_outside_original_finger_chain_capsule': True,
    'thumb_web_lateral_blend_range_metres': [.020, .045],
    'thumb_web_distal_taper_range_metres': [.085, .110],
    'nonthumb_chain_distance_blend_range_metres': [.018, .034],
    'previous_records_preserved_except_reviewed_web_vertices': [444, 479],
    'method': 'Unpatched source central palm within explicit Hand-rest-space bounds receives Hand/proximal weights. Thumb-side web uses a continuous20–45mm lateral smoothstep and85–110mm distal taper; other families use an18–34mm chain-distance envelope. Preserve originalnon-hand mass exactly.',
}
WEB_PROPORTIONS = {
    479: {'RightHand': .025, 'RightHandIndex1': .073125, 'RightHandMiddle1': .901875},
    444: {'RightHandIndex1': .125, 'RightHandMiddle1': .875},
}


def frozen_revision_2(patch):
    """Recover and verify every frozen row, including the two revised rows."""
    if patch.get('patch_revision') == 5:
        patch = frozen_revision_4(patch)
    if patch.get('patch_revision') == 4:
        patch = frozen_revision_3(patch)
    original = copy.deepcopy(patch)
    rows = [copy.deepcopy(row.get('frozen_revision_2_row', row))
            for row in patch['vertices'] if row.get('finger') != 'Palm']
    digest = hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if len(rows) != 791 or digest != FROZEN_ROWS_SHA256:
        raise ValueError('The 791 frozen revision-2 source records do not match.')
    original['vertices'] = rows
    original['changed_vertices'] = 791
    original['patch_revision'] = 2
    original['previous_patch_sha256'] = REVISION_2_PARENT_SHA256
    original.pop('frozen_revision_2_rows_sha256', None)
    original['eligibility'].pop('palm_extension', None)
    original['eligibility'].pop('reviewed_proximal_index_middle_web_vertices', None)
    if original['method'].endswith(METHOD_SUFFIX):
        original['method'] = original['method'][:-len(METHOD_SUFFIX)]
    original['counts'] = {side: {family: 0 for family in FAMILIES} for side in ('Right', 'Left')}
    for row in rows:
        original['counts'][row['side']][row['finger']] += 1
    return original


def make_revision_3(body, rig, previous_patch):
    """Return deterministic revision-3 rows without mutating Blender data."""
    if body.name != 'Human_Body' or len(body.data.vertices) != 4868 or len(rig.data.bones) != 59:
        raise ValueError('Use the untouched 4868-vertex Human_Body and 59-bone Human_Rig.')
    frozen = frozen_revision_2(previous_patch)
    to_rig = rig.matrix_world.inverted() @ body.matrix_world
    inverse_hands = {side: rig.data.bones[side + 'Hand'].matrix_local.inverted()
                     for side in ('Right', 'Left')}
    chains = {side: {family: [
        (rig.data.bones[f'{side}Hand{family}{i}'].head_local.copy(),
         rig.data.bones[f'{side}Hand{family}{i}'].tail_local.copy(),
         rig.data.bones[f'{side}Hand{family}{i}'].length)
        for i in range(1, 4)] for family in FAMILIES} for side in ('Right', 'Left')}
    original_weights = [
        {body.vertex_groups[g.group].name: float(g.weight) for g in vertex.groups if g.weight > 1e-8}
        for vertex in body.data.vertices]
    prior_indices = {row['vertex'] for row in frozen['vertices']}
    palm_rows = []
    for vertex in body.data.vertices:
        if vertex.index in prior_indices or vertex.index in (741, 742):
            continue
        old = original_weights[vertex.index]
        point = to_rig @ vertex.co
        for side in ('Right', 'Left'):
            hand = side + 'Hand'
            mass = sum(value for name, value in old.items() if name.startswith(hand))
            local = inverse_hands[side] @ point
            if (mass < .5 or not .025 <= local.y <= .110 or abs(local.x) > .052
                    or not -.035 <= local.z <= .030):
                continue
            family, (distance, arc, segment) = min(
                ((family, _nearest_chain(point, chain)) for family, chain in chains[side].items()),
                key=lambda item: item[1][0])
            if distance <= .026 and arc >= -.018:
                continue
            lateral = local.x * (1 if side == 'Left' else -1)
            blend_family, blend_arc = family, arc
            if lateral > .020:
                blend_family = 'Thumb'
                blend_arc = _nearest_chain(point, chains[side]['Thumb'])[1]
                envelope = _smooth((lateral - .020) / .025) * (1 - _smooth((local.y - .085) / .025))
            else:
                envelope = 1 - _smooth((distance - .018) / .016)
            partial = _finger_weights(side, blend_family, blend_arc,
                                      [part[2] for part in chains[side][blend_family]])
            partial = {name: value * envelope for name, value in partial.items()}
            partial[hand] = partial.get(hand, 0) + (1 - envelope)
            total = sum(partial.values())
            partial = {name: value / total for name, value in partial.items() if value > 1e-8}
            new = {name: value for name, value in old.items() if not name.startswith(hand)}
            new.update({name: value * mass for name, value in partial.items() if value * mass > 1e-8})
            if len(new) > 4:
                continue
            if max(abs(new.get(name, 0) - old.get(name, 0)) for name in set(new) | set(old)) < 1e-6:
                continue
            palm_rows.append({
                'vertex': vertex.index, 'position_blender': list(vertex.co),
                'position_gltf': [vertex.co.x, vertex.co.z, -vertex.co.y],
                'old_weights': [{'bone': name, 'weight': value} for name, value in sorted(old.items())],
                'weights': [{'bone': name, 'weight': value} for name, value in sorted(new.items())],
                'side': side, 'finger': 'Palm', 'hand_local_y': float(local.y),
                'nearest_chain_distance': distance, 'chain_arc_metres': arc,
                'nearest_family': family, 'hand_local_position': list(local),
                'blend_family': blend_family, 'blend_chain_arc_metres': blend_arc,
                'reason': 'Bounded central palm outside original finger-chain patch; stabilize remote phalanx motion, blend the thumb web laterally, preserve all non-hand mass.',
            })
    result = copy.deepcopy(frozen)
    result['patch_revision'] = 3
    result['previous_patch_sha256'] = FROZEN_PATCH_SHA256
    result['frozen_revision_2_rows_sha256'] = FROZEN_ROWS_SHA256
    result['vertices'].extend(palm_rows)
    result['changed_vertices'] = len(result['vertices'])
    result['eligibility']['palm_extension'] = copy.deepcopy(PALM_SPEC)
    result['eligibility']['reviewed_proximal_index_middle_web_vertices'] = [444, 479]
    result['method'] = frozen['method'] + METHOD_SUFFIX
    for side in ('Right', 'Left'):
        result['counts'][side]['Palm'] = sum(row['side'] == side for row in palm_rows)
    neighbors = {index: [] for index in WEB_PROPORTIONS}
    for edge in body.data.edges:
        a, b = edge.vertices
        if a in neighbors:
            neighbors[a].append(b)
        if b in neighbors:
            neighbors[b].append(a)
    for number, row in enumerate(result['vertices']):
        index = row['vertex']
        if index not in WEB_PROPORTIONS:
            continue
        modified = copy.deepcopy(row)
        old = original_weights[index]
        mass = sum(value for name, value in old.items() if name.startswith('RightHand'))
        target = {name: value for name, value in old.items() if not name.startswith('RightHand')}
        target.update({name: value * mass for name, value in WEB_PROPORTIONS[index].items()})
        modified.update({
            'finger': 'IndexMiddleWeb', 'eligibility_exception': 'source_proximal_index_middle_web',
            'frozen_revision_2_row': row, 'source_neighbors': sorted(neighbors[index]),
            'same_hand_proportions': copy.deepcopy(WEB_PROPORTIONS[index]),
            'weights': [{'bone': name, 'weight': value} for name, value in sorted(target.items())],
            'reason': 'Reviewed proximal index/middle mesh junction: blend neighboring proximal roots; preserve original non-hand mass and every rest/UV/morph coordinate.',
        })
        result['vertices'][number] = modified
    result['counts']['Right']['Index'] -= 2
    result['counts']['Right']['IndexMiddleWeb'] = 2
    return result


def frozen_revision_3(patch):
    """Recover every revision-3 record without trusting new row replacements."""
    if patch.get('patch_revision') == 5:
        patch = frozen_revision_4(patch)
    original = copy.deepcopy(patch)
    rows = [copy.deepcopy(row.get('frozen_revision_3_row', row))
            for row in patch['vertices']]
    digest = hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if len(rows) != 1060 or digest != REVISION_3_ROWS_SHA256:
        raise ValueError('The 1060 frozen revision-3 source records do not match.')
    original['vertices'] = rows
    original['changed_vertices'] = 1060
    original['patch_revision'] = 3
    original['previous_patch_sha256'] = FROZEN_PATCH_SHA256
    original.pop('frozen_revision_3_rows_sha256', None)
    original['eligibility'].pop('reviewed_distal_middle_topology_vertices', None)
    if original['method'].endswith(DISTAL_METHOD_SUFFIX):
        original['method'] = original['method'][:-len(DISTAL_METHOD_SUFFIX)]
    for side in original['counts']:
        for family in original['counts'][side]:
            original['counts'][side][family] = 0
    for row in rows:
        original['counts'][row['side']][row['finger']] += 1
    return original


def make_revision_4(body, rig, previous_patch):
    """Return the seven-row topology correction on the exact revision-3 base.

The original mesh and armature are read only. The same adjacent-phalanx
distribution as the original hand author is evaluated on the Middle chain;
only the chain ownership changes. All original non-hand influence is kept.
    """
    base = make_revision_3(body, rig, previous_patch)
    if frozen_revision_3(base) != base:
        raise ValueError('Revision-3 reconstruction differs from its frozen base.')
    to_rig = rig.matrix_world.inverted() @ body.matrix_world
    chain = [(rig.data.bones[f'RightHandMiddle{i}'].head_local.copy(),
              rig.data.bones[f'RightHandMiddle{i}'].tail_local.copy(),
              rig.data.bones[f'RightHandMiddle{i}'].length)
             for i in range(1, 4)]
    neighbors = {index: [] for index in DISTAL_MIDDLE_VERTICES}
    for edge in body.data.edges:
        a, b = edge.vertices
        if a in neighbors:
            neighbors[a].append(b)
        if b in neighbors:
            neighbors[b].append(a)
    result = copy.deepcopy(base)
    for number, row in enumerate(base['vertices']):
        index = row['vertex']
        if index not in neighbors:
            continue
        if row['side'] != 'Right' or row['finger'] != 'Ring':
            raise ValueError('Reviewed distal ownership source row changed: ' + str(index))
        vertex = body.data.vertices[index]
        old = {body.vertex_groups[g.group].name: float(g.weight)
               for g in vertex.groups if g.weight > 1e-8}
        mass = sum(value for name, value in old.items() if name.startswith('RightHand'))
        distance, arc, segment = _nearest_chain(to_rig @ vertex.co, chain)
        partial = _finger_weights('Right', 'Middle', arc, [part[2] for part in chain])
        target = {name: value for name, value in old.items() if not name.startswith('RightHand')}
        target.update({name: value * mass for name, value in partial.items() if value * mass > 1e-8})
        modified = copy.deepcopy(row)
        modified.update({
            'finger': 'Middle',
            'eligibility_exception': 'source_distal_middle_topology',
            'frozen_revision_3_row': copy.deepcopy(row),
            'frozen_revision_2_row': copy.deepcopy(row.get('frozen_revision_2_row', row)),
            'source_neighbors': sorted(neighbors[index]),
            'same_hand_proportions': copy.deepcopy(partial),
            'nearest_chain_distance': distance,
            'chain_arc_metres': arc,
            'weights': [{'bone': name, 'weight': value} for name, value in sorted(target.items())],
            'reason': 'Source topology and original Middle-family influence place this vertex on the Middle pad. Use the existing Middle-chain adjacent-phalanx distribution; preserve all non-hand mass and every geometry/rest/morph coordinate.',
        })
        result['vertices'][number] = modified
    result['patch_revision'] = 4
    result['previous_patch_sha256'] = REVISION_3_PATCH_SHA256
    result['frozen_revision_3_rows_sha256'] = REVISION_3_ROWS_SHA256
    result['eligibility']['reviewed_distal_middle_topology_vertices'] = list(DISTAL_MIDDLE_VERTICES)
    result['method'] = base['method'] + DISTAL_METHOD_SUFFIX
    result['counts']['Right']['Ring'] -= len(DISTAL_MIDDLE_VERTICES)
    result['counts']['Right']['Middle'] += len(DISTAL_MIDDLE_VERTICES)
    if frozen_revision_3(result) != base:
        raise ValueError('Revision-4 rows do not recover the exact revision-3 base.')
    return result


def frozen_revision_4(patch):
    """Recover the exact previous skin patch from four reviewed left rows."""
    original = copy.deepcopy(patch)
    rows = [copy.deepcopy(row.get('frozen_revision_4_row', row))
            for row in patch['vertices']]
    digest = hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if len(rows) != 1060 or digest != REVISION_4_ROWS_SHA256:
        raise ValueError('The 1060 frozen revision-4 source records do not match.')
    original['vertices'] = rows
    original['changed_vertices'] = 1060
    original['patch_revision'] = 4
    original['previous_patch_sha256'] = REVISION_3_PATCH_SHA256
    original.pop('frozen_revision_4_rows_sha256', None)
    original['eligibility'].pop('reviewed_left_distal_middle_topology_vertices', None)
    original['eligibility'].pop('reviewed_left_middle_ring_web', None)
    if original['method'].endswith(LEFT_DISTAL_METHOD_SUFFIX):
        original['method'] = original['method'][:-len(LEFT_DISTAL_METHOD_SUFFIX)]
    elif original['method'].endswith(LEFT_DISTAL_PURE_TRIAL_SUFFIX):
        original['method'] = original['method'][:-len(LEFT_DISTAL_PURE_TRIAL_SUFFIX)]
    for side in original['counts']:
        for family in original['counts'][side]:
            original['counts'][side][family] = 0
    for row in rows:
        original['counts'][row['side']][row['finger']] += 1
    return original


def make_revision_5(body, rig, previous_patch):
    """Return only the four-row left Middle ownership correction.

    At hand-local y > 0.15 m these rows belong to the topology-separated
    Middle component. Reuse the existing adjacent-phalanx distribution
    on that chain; at the proximal web 4597 mix it equally with the previous
    Ring-chain distribution, preserving exact original hand/non-hand mass.
    The source body, rest rig, UVs and shape coordinates are read only.
    This improves local deformation; it is not a collision-clearance test.
    """
    base = make_revision_4(body, rig, previous_patch)
    if frozen_revision_4(base) != base:
        raise ValueError('Revision-4 reconstruction differs from its frozen base.')
    to_rig = rig.matrix_world.inverted() @ body.matrix_world
    chain = [(rig.data.bones[f'LeftHandMiddle{i}'].head_local.copy(),
              rig.data.bones[f'LeftHandMiddle{i}'].tail_local.copy(),
              rig.data.bones[f'LeftHandMiddle{i}'].length) for i in range(1, 4)]
    neighbors = {index: [] for index in LEFT_DISTAL_MIDDLE_VERTICES}
    for edge in body.data.edges:
        a, b = edge.vertices
        if a in neighbors:
            neighbors[a].append(b)
        if b in neighbors:
            neighbors[b].append(a)
    result = copy.deepcopy(base)
    for number, row in enumerate(base['vertices']):
        index = row['vertex']
        if index not in neighbors:
            continue
        if row['side'] != 'Left' or row['finger'] != 'Ring':
            raise ValueError('Reviewed left distal ownership source row changed: ' + str(index))
        vertex = body.data.vertices[index]
        old = {body.vertex_groups[g.group].name: float(g.weight)
               for g in vertex.groups if g.weight > 1e-8}
        mass = sum(value for name, value in old.items() if name.startswith('LeftHand'))
        distance, arc, segment = _nearest_chain(to_rig @ vertex.co, chain)
        partial = _finger_weights('Left', 'Middle', arc, [part[2] for part in chain])
        if index == LEFT_MIDDLE_RING_WEB['vertex']:
            ring = {part['bone']: part['weight'] for part in row['weights']
                    if part['bone'].startswith('LeftHandRing')}
            if len(ring) != 2 or abs(sum(ring.values()) - 1.0) > 1e-7:
                raise ValueError('Reviewed proximal web Ring distribution changed.')
            ring_total = sum(ring.values())
            partial = {name: .5 * value for name, value in partial.items()}
            partial.update({name: .5 * value / ring_total for name, value in ring.items()})
        target = {name: value for name, value in old.items() if not name.startswith('LeftHand')}
        target.update({name: value * mass for name, value in partial.items() if value * mass > 1e-8})
        modified = copy.deepcopy(row)
        modified.update({
            'finger': 'Middle',
            'eligibility_exception': 'source_left_distal_middle_topology',
            'frozen_revision_4_row': copy.deepcopy(row),
            'source_neighbors': sorted(neighbors[index]),
            'same_hand_proportions': copy.deepcopy(partial),
            'nearest_chain_distance': distance,
            'chain_arc_metres': arc,
            'weights': [{'bone': name, 'weight': value} for name, value in sorted(target.items())],
            'reason': 'Topology-separated left Middle component: retain Middle ownership instead of nearest Ring chain; reuse adjacent-phalanx weighting and preserve original non-hand mass and all mesh/rest/morph coordinates.',
        })
        if index == LEFT_MIDDLE_RING_WEB['vertex']:
            modified['web_blend'] = copy.deepcopy(LEFT_MIDDLE_RING_WEB)
            modified['reason'] = 'Reviewed proximal Middle/Ring mesh junction: blend Middle-chain and previous Ring-chain distributions equally; preserve original hand/non-hand mass, four-influence limit and every mesh/rest/morph coordinate.'
        result['vertices'][number] = modified
    result['patch_revision'] = 5
    result['previous_patch_sha256'] = REVISION_4_PATCH_SHA256
    result['frozen_revision_4_rows_sha256'] = REVISION_4_ROWS_SHA256
    result['eligibility']['reviewed_left_distal_middle_topology_vertices'] = list(LEFT_DISTAL_MIDDLE_VERTICES)
    result['eligibility']['reviewed_left_middle_ring_web'] = copy.deepcopy(LEFT_MIDDLE_RING_WEB)
    result['method'] = base['method'] + LEFT_DISTAL_METHOD_SUFFIX
    result['counts']['Left']['Ring'] -= len(LEFT_DISTAL_MIDDLE_VERTICES)
    result['counts']['Left']['Middle'] += len(LEFT_DISTAL_MIDDLE_VERTICES)
    if frozen_revision_4(result) != base:
        raise ValueError('Revision-5 rows do not recover the exact revision-4 base.')
    return result
