# SPDX-License-Identifier: 0BSD
"""Fit a closed cylindrical grip against the deformed R11 hand surface."""
import math
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

def fit_grip(rig,body,grip,fingers):
    for name,pose in fingers.items():rig.pose.bones[name].matrix_basis=pose
    names={g.index:g.name for g in body.vertex_groups}
    vertices=[];weights=[];labels=[]
    bones=list(rig.pose.bones);indices={b.name:i for i,b in enumerate(bones)}
    for vertex in body.data.vertices:
        groups=[(names[g.group],g.weight) for g in vertex.groups if names[g.group] in indices]
        if sum(w for n,w in groups if n.startswith('RightHand'))<.8:continue
        vertices.append((*vertex.co,1.0));weights.append(groups)
        labels.append(max(groups,key=lambda x:x[1])[0])
    vertices=np.array(vertices,dtype=np.float64);labels=np.array(labels)
    weight_matrix=np.zeros((len(vertices),len(bones)))
    for i,row in enumerate(weights):
        for name,weight in row:weight_matrix[i,indices[name]]=weight
    used=np.where(weight_matrix.sum(axis=0)>0)[0]
    inverse=[b.bone.matrix_local.inverted() for b in bones]
    def skin():
        result=np.zeros((len(vertices),3))
        for index in used:
            matrix=np.array(bones[index].matrix@inverse[index])
            result+=(vertices@matrix.T)[:,:3]*weight_matrix[:,index,None]
        return result
    def set_hand():
        rig.pose.bones['RightHand'].matrix=grip;bpy.context.view_layer.update()
    # The source axe grip puts the shaft through the fleshy edge of this palm.
    # Move it out to the palm surface before wrapping each separate finger.
    grip.translation.y+=.018
    set_hand()
    # Exclude wrist-transition vertices influenced by the forearm while this
    # static fitting pose has only the hand moved into tool-local coordinates.
    palm=(labels=='RightHand')&(weight_matrix[:,indices['RightHand']]>.999)
    for _ in range(20):
        points=skin()[palm];radius=np.linalg.norm(points[:,:2],axis=1)
        if radius.min()>=.0225:break
        grip.translation.y+=.001;set_hand()
    def aim(bone,target):
        at=bone.matrix.copy();q=at.to_quaternion()
        q=(q@Vector((0,1,0))).rotation_difference((Vector(target)-at.translation).normalized())@q
        bone.matrix=Matrix.LocRotScale(at.translation,q,Vector((1,1,1)));bpy.context.view_layer.update()
    # Actual proximal/intermediate/distal bone directions, around the cylinder.
    # Their lengths remain unchanged and each metacarpal starts at its own station.
    for finger in ['Index','Middle','Ring','Pinky']:
        z=rig.pose.bones['RightHand'+finger+'1'].head.z
        for joint,(x,y) in enumerate([(-.036,.012),(-.025,-.022),(.001,-.033)],1):
            aim(rig.pose.bones[f'RightHand{finger}{joint}'],(x,y,z))
    for joint,target in enumerate([(.045,.015,.060),(.025,-.020,.065),(0,-.036,.050)],1):
        aim(rig.pose.bones[f'RightHandThumb{joint}'],target)
    report={}
    # Small bounded adjustments use the actual weighted surface, not just bone
    # centres. Penalize penetration strongly while keeping distal pads in contact.
    for finger in ['Index','Middle','Ring','Pinky','Thumb']:
        chain=[rig.pose.bones[f'RightHand{finger}{j}'] for j in [1,2,3]]
        base=[b.rotation_quaternion.copy() for b in chain]
        selected=np.char.startswith(labels,'RightHand'+finger)
        distal=np.char.startswith(labels,'RightHand'+finger+'3')
        tip_distance=np.linalg.norm(vertices[:,:3]-np.array(chain[-1].bone.tail_local),axis=1)
        tip_candidates=np.where(distal)[0]
        tip_indices=tip_candidates[np.argsort(tip_distance[tip_candidates])[:12]]
        dimensions=6 if finger=='Thumb' else 3
        values=[0.0]*dimensions
        def apply(values):
            for i,bone in enumerate(chain):
                q=base[i]@Quaternion((1,0,0),values[i])
                if dimensions==6:q=q@Quaternion((0,0,1),values[i+3])
                bone.rotation_quaternion=q
            bpy.context.view_layer.update()
        def score():
            points=skin();r=np.linalg.norm(points[:,:2],axis=1)
            penetration=np.maximum(0,.023-r[selected])
            tip=r[tip_indices]
            return float(1000*penetration.max()**2+30*np.mean(penetration**2)+4*(tip.min()-.024)**2+.000002*sum(v*v for v in values))
        apply(values);best=score()
        for step in [.25,.12,.06,.03,.015,.0075]:
            for iteration in range(8):
                improved=False
                for axis in range(dimensions):
                    original=values[axis];chosen=original
                    for direction in [-1,1]:
                        values[axis]=max(-.7,min(.7,original+direction*step));apply(values);candidate=score()
                        if candidate<best:best=candidate;chosen=values[axis];improved=True
                    values[axis]=chosen;apply(values)
                if not improved:break
        points=skin();radius=np.linalg.norm(points[selected,:2],axis=1)
        report[finger]={'minimum_skin_radius':float(radius.min()),'adjustments_radians':values}
    for name in fingers:fingers[name]=rig.pose.bones[name].matrix_basis.copy()
    report['palm_minimum_skin_radius']=float(np.linalg.norm(skin()[palm,:2],axis=1).min())
    report['fitted_vertices']=len(vertices)
    return grip,fingers,report
