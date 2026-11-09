# SPDX-License-Identifier: CC0-1.0
"""Optional Human R11 first-person hand skin patch; original mesh stays intact.

The patch changes hand-bone influences only. Rest positions, topology, UVs,
materials, normals and all shape-key coordinates are untouched. Work on a
single-user mesh copy named Human_FP_Hands, never the supplied Human_Body.
Uses native Blender APIs and Python's standard library only.
"""
import math
from mathutils import Vector

SOURCE_GLB_SHA256 = '0dc8fdbcfac451f61b6eee5c914b1e79f5ec450f5e98e4c896e8b46370bf35c8'
FAMILIES = ('Index', 'Middle', 'Ring', 'Pinky', 'Thumb')


def _smooth(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3 - 2 * value)


def _nearest_chain(point, chain):
    best = None
    offset = 0.0
    for i, (a, b, length) in enumerate(chain):
        direction = b - a
        t = (point - a).dot(direction) / (length * length)
        tc = max(0.0, min(1.0, t))
        distance = (point - (a + direction * tc)).length
        arc = offset + length * tc
        if i == 0 and t < 0:
            arc = length * t
        if best is None or distance < best[0]:
            best = (distance, arc, i)
        offset += length
    return best


def _finger_weights(prefix, family, arc, lengths):
    hand = prefix + 'Hand'
    bones = [hand + family + str(i) for i in range(1, 4)]
    # Blend the web/palm into its own proximal digit. Distal skin cannot
    # inherit a neighboring digit when the index is extended independently.
    if arc < .014:
        t = _smooth((arc + .018) / .032)
        return {hand: 1-t, bones[0]: t}
    first = lengths[0]
    second = lengths[0] + lengths[1]
    width1 = min(.008, lengths[0] * .27, lengths[1] * .27)
    width2 = min(.007, lengths[1] * .27, lengths[2] * .27)
    if arc < first-width1:
        return {bones[0]: 1.0}
    if arc <= first+width1:
        t = _smooth((arc-(first-width1))/(2*width1))
        return {bones[0]: 1-t, bones[1]: t}
    if arc < second-width2:
        return {bones[1]: 1.0}
    if arc <= second+width2:
        t = _smooth((arc-(second-width2))/(2*width2))
        return {bones[1]: 1-t, bones[2]: t}
    return {bones[2]: 1.0}


def make_hand_patch(body, rig):
    """Return a serializable named-bone patch from the original R11 weights."""
    if len(body.data.vertices) != 4868 or len(rig.data.bones) != 59:
        raise ValueError('This patch author targets the supplied Human R11 body/rig.')
    to_rig = rig.matrix_world.inverted() @ body.matrix_world
    inverse_hands = {side: rig.data.bones[side+'Hand'].matrix_local.inverted() for side in ('Right','Left')}
    chains = {}
    for side in ('Right','Left'):
        chains[side] = {}
        for family in FAMILIES:
            chains[side][family] = [(rig.data.bones[f'{side}Hand{family}{i}'].head_local.copy(),
                                     rig.data.bones[f'{side}Hand{family}{i}'].tail_local.copy(),
                                     rig.data.bones[f'{side}Hand{family}{i}'].length) for i in range(1,4)]
    rows = []
    counts = {side: {family:0 for family in FAMILIES} for side in ('Right','Left')}
    skipped_limit = []
    max_non_hand_delta = 0.0
    for vertex in body.data.vertices:
        old = {body.vertex_groups[g.group].name: float(g.weight) for g in vertex.groups if g.weight > 1e-8}
        point = to_rig @ vertex.co
        for side in ('Right','Left'):
            prefix = side+'Hand'
            hand_mass = sum(weight for name,weight in old.items() if name.startswith(prefix))
            local = inverse_hands[side] @ point
            if hand_mass < .5 or local.y < .025:
                continue
            candidates = [(family, _nearest_chain(point, chain)) for family,chain in chains[side].items()]
            family, (distance, arc, segment) = min(candidates, key=lambda row:row[1][0])
            if distance > .026 or arc < -.018:
                continue
            partial = _finger_weights(side, family, arc, [segment[2] for segment in chains[side][family]])
            new = {name:weight for name,weight in old.items() if not name.startswith(prefix)}
            for name,weight in partial.items():
                if weight * hand_mass > 1e-8:
                    new[name] = weight * hand_mass
            total = sum(new.values())
            new = {name:weight/total for name,weight in new.items() if weight/total > 1e-8}
            if len(new) > 4:
                skipped_limit.append(vertex.index)
                continue
            delta = max(abs(new.get(name,0)-old.get(name,0)) for name in set(new)|set(old))
            if delta < 1e-6:
                continue
            for name in set(old)|set(new):
                if not name.startswith(prefix):
                    max_non_hand_delta = max(max_non_hand_delta,abs(new.get(name,0)-old.get(name,0)))
            xyz = list(vertex.co)
            rows.append({'vertex':vertex.index,'position_blender':xyz,
                         'position_gltf':[xyz[0],xyz[2],-xyz[1]],
                         'old_weights':[{'bone':name,'weight':old[name]} for name in sorted(old)],
                         'weights':[{'bone':name,'weight':new[name]} for name in sorted(new)],
                         'side':side, 'finger':family,
                         'hand_local_y':float(local.y), 'nearest_chain_distance':float(distance),
                         'chain_arc_metres':float(arc)})
            counts[side][family] += 1
            break
    return {'schema':'human-r11-fp-hand-skin-patch-1',
        'source_mesh':'Human_Body','variant_mesh':'Human_FP_Hands',
        'source_vertex_count':4868,'source_bone_count':59,
        'source_glb_sha256':SOURCE_GLB_SHA256,
        'position_space':'Authored body mesh rest positions, Blender metres; position_gltf=(x,z,-y).',
        'weights_use':'Exact original Human R11 bone names; resolve through the imported named Skin bind.',
        'eligibility':{'minimum_original_same_hand_weight_sum':.5,
                       'minimum_hand_rest_local_y_metres':.025,
                       'maximum_nearest_finger_chain_distance_metres':.026,
                       'minimum_chain_arc_metres':-.018,
                       'maximum_output_influences':4},
        'preserved':'Positions, topology, UVs, material assignments, normals, 229 shape-key blocks and skeleton rest data.',
        'method':'Own-finger nearest rest-chain assignment; smooth adjacent-phalanx weights and palm/proximal transition. Existing non-hand influence mass retained, with only normalization rounding.',
        'changed_vertices':len(rows),'counts':counts,
        'maximum_non_hand_weight_delta':max_non_hand_delta,
        'skipped_due_to_four_influence_limit':skipped_limit,
        'vertices':rows}


def apply_hand_patch(bodycopy, rig, patch=None):
    """Apply to a separate single-user Human_FP_Hands mesh object.

    Return the patch so callers can save it verbatim for native reintegration.
    A source named Human_Body is protected against accidental mutation.
    """
    if bodycopy.name == 'Human_Body':
        raise ValueError('Preserve Human_Body; apply to a separate Human_FP_Hands copy.')
    if bodycopy.data.users != 1:
        raise ValueError('Duplicate mesh data before changing weights; mesh must be single-user.')
    patch = patch or make_hand_patch(bodycopy,rig)
    if patch['source_vertex_count'] != len(bodycopy.data.vertices):
        raise ValueError('Wrong body vertex count.')
    for row in patch['vertices']:
        vertex = bodycopy.data.vertices[row['vertex']]
        if (vertex.co-Vector(row['position_blender'])).length > 1e-7:
            raise ValueError('Source position differs at vertex ' + str(row['vertex']))
        for group in list(vertex.groups):
            bodycopy.vertex_groups[group.group].remove([vertex.index])
        for influence in row['weights']:
            name = influence['bone']
            if name not in rig.data.bones:
                raise ValueError('Unknown bone ' + name)
            group = bodycopy.vertex_groups.get(name) or bodycopy.vertex_groups.new(name=name)
            group.add([vertex.index], influence['weight'], 'REPLACE')
    return patch
