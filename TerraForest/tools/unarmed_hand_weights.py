# SPDX-License-Identifier: 0BSD
"""Repair finger cross weighting; retain original rest geometry and rig."""
import math
from mathutils import Vector

def repair_hand(body, rig, side):
    inverse = rig.data.bones[side+'Hand'].matrix_local.inverted()
    chains = {}
    for finger in ['Index','Middle','Ring','Pinky','Thumb']:
        bones = [rig.data.bones[f'{side}Hand{finger}{i}'] for i in [1,2,3]]
        points = [inverse @ bone.head_local for bone in bones] + [inverse @ bones[-1].tail_local]
        lengths = [(b-a).length for a,b in zip(points,points[1:])]
        chains[finger] = (points,lengths)
    def closest(point, points, lengths):
        best = (math.inf,0.0); start = 0.0
        for a,b,length in zip(points,points[1:],lengths):
            t = max(0,min(1,(point-a).dot(b-a)/(length*length)))
            distance = (point-a.lerp(b,t)).length
            if distance < best[0]: best = (distance,start+t*length)
            start += length
        return best
    names = {g.index:g.name for g in body.vertex_groups}
    basis = body.data.shape_keys.key_blocks['Basis']
    rows = []; counts = {}; cross_before = 0
    for vertex in body.data.vertices:
        weights = {names[g.group]:g.weight for g in vertex.groups}
        finger_weight = sum(w for name,w in weights.items() if name.startswith(side+'Hand') and name != side+'Hand')
        if finger_weight < .12: continue
        point = inverse @ basis.data[vertex.index].co
        candidates = {finger:closest(point,*chain) for finger,chain in chains.items()}
        finger = min(candidates,key=lambda f:candidates[f][0])
        distance,s = candidates[finger]; points,lengths = chains[finger]
        # Retain the palm/web at the proximal joint and blend each hinge over
        # a short anatomical band. Distal joints never pull adjacent fingers.
        knots = [-.014, 0.0, lengths[0], lengths[0]+lengths[1]]
        # The MCP may project to s=0 from the web; signed projection separates
        # palm-side vertices from the proximal phalanx.
        if s < .00001: s = (point-points[0]).dot((points[1]-points[0]).normalized())
        transitions = [(0.0,.012,side+'Hand',f'{side}Hand{finger}1'),
                       (knots[2],.009,f'{side}Hand{finger}1',f'{side}Hand{finger}2'),
                       (knots[3],.008,f'{side}Hand{finger}2',f'{side}Hand{finger}3')]
        result = {side+'Hand':1.0}
        for center,width,left,right in transitions:
            if s < center-width: break
            if s > center+width: result = {right:1.0}; continue
            t = (s-center+width)/(2*width); t = t*t*(3-2*t)
            result = {left:1-t,right:t}; break
        result = {n:w for n,w in result.items() if w>.000001}
        foreign = sum(w for n,w in weights.items() if n.startswith(side+'Hand') and n!=side+'Hand' and not n.startswith(side+'Hand'+finger))
        if foreign>.1: cross_before += 1
        for group in list(vertex.groups): body.vertex_groups[group.group].remove([vertex.index])
        for name,weight in result.items(): body.vertex_groups[name].add([vertex.index],weight,'REPLACE')
        p = basis.data[vertex.index].co
        rows.append({'position':[p.x,p.z,-p.y], 'weights':result})
        counts[finger] = counts.get(finger,0)+1
    return {'vertices':rows,'counts':counts,'cross_finger_vertices_before':cross_before,'scope':'Finger weights only; unchanged rest geometry, skin bind and materials. Runtime uses a separate mesh only with empty hands.'}
