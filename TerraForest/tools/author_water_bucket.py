# SPDX-License-Identifier: 0BSD
"""Blender: detailed metal pail and a fixed carry grip on the original R11 rig."""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'addons/characters/authoring'
ASSETS = ROOT/'addons/volumetric_water/assets'
ASSETS.mkdir(parents=True, exist_ok=True)
source = Path(bpy.data.filepath)
assert source.name == 'Human.r11.blend'
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
sys.path.insert(0,str(ROOT/'tools'))
from unarmed_hand_weights import repair_hand
for side in ['Left','Right']:repair_hand(bpy.data.objects['Human_Body'],rig,side)
FPS = 60
DURATIONS = {'Idle':2.0, 'Walk':1.0, 'Run':.8, 'Jump':1.5, 'Scoop':2.4, 'Pour':2.8}
BONE = 'Weapon_Axe'
PAIL_BONE = 'Weapon_Pickaxe'
HANDLE_RISE = .102
HINGE = Vector((0, 0, -.118-HANDLE_RISE))


def sample(action, frame):
    rig.animation_data_create()
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(int(frame), subframe=frame-int(frame))
    bpy.context.view_layer.update()
    return {b.name:b.matrix_basis.copy() for b in rig.pose.bones}


base = sample(bpy.data.actions['FP_Axe_Idle'], 1)
old_tool = rig.pose.bones[BONE].matrix.copy()
old_hand = old_tool.inverted() @ rig.pose.bones['RightHand'].matrix
old_hand.translation.z = 0
# An overhand carry: wrist behind the sleeve, palm down, fingers underneath.
# The previous vertical fist put the wrist below the handle like a mug grip.
grip = Matrix.Rotation(math.radians(65), 4, 'X') @ Matrix.Rotation(math.pi/2, 4, 'Y') @ old_hand
fingers = {name:matrix for name,matrix in base.items() if 'RightHand' in name and name!='RightHand'}
with bpy.data.libraries.load(str(OUT/'Human.unarmed.blend'),link=False) as (available,loaded):
    loaded.actions=['FP_Unarmed_Idle','FP_Unarmed_Punch']
neutral=sample(bpy.data.actions['FP_Unarmed_Idle'],0)
closed=sample(bpy.data.actions['FP_Unarmed_Punch'],28)
for name,matrix in closed.items():
    if 'RightHandThumb' in name:fingers[name]=matrix
gaits = {}
for motion in ['Walk','Run','Jump']:
    action = bpy.data.actions[motion]
    start,end = action.frame_range
    count = round(DURATIONS[motion]*FPS)
    gaits[motion] = [sample(action,start+(end-start)*i/count) for i in range(count+1)]
    if motion!='Jump':gaits[motion][-1]=gaits[motion][0]
for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type=='MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            if key.name!='Basis':key.value=0
for action in list(bpy.data.actions):bpy.data.actions.remove(action)
for bone in rig.pose.bones:
    bone.rotation_mode='QUATERNION';bone.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
rest = {b.name:b.matrix.copy() for b in rig.pose.bones}


def material(name, color, metallic, roughness):
    mat=bpy.data.materials.new(name);mat.diffuse_color=(*color,1);mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    for key,value in [('Base Color',(*color,1)),('Metallic',metallic),('Roughness',roughness)]:bsdf.inputs[key].default_value=value
    return mat


def maps(mat, wood=False):
    size=1024;rng=np.random.default_rng(648 if wood else 276)
    y,x=np.mgrid[0:size,0:size].astype(np.float32)/size
    noise=rng.normal(0,1,(size,size)).astype(np.float32)
    if wood:
        grain=np.sin(x*260+np.sin(y*9)*4+np.sin(x*41+y*7)*2)
        broad=np.sin(x*36+np.sin(y*8)*.8)
        color=np.array([.33,.19,.085])[None,None,:]*(1+grain[...,None]*.12+broad[...,None]*.1)
        rough=np.clip(.56+grain*.05+noise*.015,.4,.7)
        height=grain*.001
    else:
        # Fine zinc mottling, long abrasion, and worn sheen without deep noise.
        mottling=(np.sin(x*77+y*39)*np.sin(y*97-x*41)+np.sin(x*213-y*163)*.35)
        brush=np.sin(y*1700+np.sin(x*21)*2)
        scratch=np.zeros((size,size),dtype=np.float32)
        for _ in range(160):
            row=int(rng.integers(0,size));col=int(rng.integers(0,size-150));length=int(rng.integers(20,150))
            scratch[row,col:col+length]=rng.uniform(.1,.6)
        color=np.clip((.65+mottling*.014+brush*.005+noise*.006+scratch*.025)[...,None]*np.array([.94,.98,1.0]),0,1)
        rough=np.clip(.46+mottling*.025+noise*.01-scratch*.10,.33,.56)
        height=mottling*.00012+brush*.000025+scratch*.0001
    dy,dx=np.gradient(height)
    normal=np.stack((-dx*140,-dy*140,np.ones_like(dx)),axis=-1)
    normal=normal/np.linalg.norm(normal,axis=-1,keepdims=True)*.5+.5
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    for label,pixels,space in [('BaseColor',color,'sRGB'),('Roughness',np.repeat(rough[...,None],3,axis=-1),'Non-Color'),('Normal',normal,'Non-Color')]:
        image=bpy.data.images.new(mat.name+'.'+label,width=size,height=size,alpha=False)
        image.colorspace_settings.name=space
        rgba=np.ones((size,size,4),dtype=np.float32);rgba[:,:,:3]=pixels
        image.pixels.foreach_set(rgba.ravel());image.update();image.pack()
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
        if label=='Normal':
            n=mat.node_tree.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.35
            mat.node_tree.links.new(node.outputs['Color'],n.inputs['Color']);mat.node_tree.links.new(n.outputs['Normal'],bsdf.inputs['Normal'])
        else:mat.node_tree.links.new(node.outputs['Color'],bsdf.inputs['Base Color' if label=='BaseColor' else 'Roughness'])


steel=material('Bucket.Galvanized steel',(.49,.53,.56),.92,.39);maps(steel)
edge=material('Bucket.Rolled edge and bail',(.48,.53,.57),.94,.28)
wood=material('Bucket.Oiled wooden grip',(.33,.19,.085),0,.56);maps(wood,True)
dark=material('Bucket.Recessed seams',(.19,.23,.25),.85,.50)
parts=[]


def mesh(name,vertices,faces,mat):
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
    obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);data.materials.append(mat)
    for polygon in data.polygons:polygon.use_smooth=True
    parts.append(obj);return obj


def lathe(name, profile, mat, segments=96):
    vertices=[(radius*math.cos(math.tau*j/segments),radius*math.sin(math.tau*j/segments),z)
              for radius,z in profile for j in range(segments)]
    faces=[]
    for row in range(len(profile)-1):
        for j in range(segments):
            a=row*segments+j;b=row*segments+(j+1)%segments
            faces.append((a,b,b+segments,a+segments))
    return mesh(name,vertices,faces,mat)


def tube(name, points, radius, mat, segments=12):
    points=[Vector(p) for p in points];vertices=[]
    for i,point in enumerate(points):
        direction=(points[min(len(points)-1,i+1)]-points[max(0,i-1)]).normalized()
        a=direction.cross(Vector((0,1,0))).normalized();b=direction.cross(a).normalized()
        for j in range(segments):vertices.append(point+radius*(a*math.cos(math.tau*j/segments)+b*math.sin(math.tau*j/segments)))
    faces=[]
    for i in range(len(points)-1):
        for j in range(segments):
            a=i*segments+j;b=i*segments+(j+1)%segments;faces.append((a,b,b+segments,a+segments))
    faces.extend([tuple(reversed(range(segments))),tuple((len(points)-1)*segments+j for j in range(segments))])
    return mesh(name,vertices,faces,mat)


# Continuous thick shell with a genuine open mouth and recessed flat inner floor.
profile=[(.001,-.335),(.102,-.335),(.111,-.332),(.114,-.326),(.115,-.314),
         (.116,-.305),(.121,-.274),(.123,-.266),(.125,-.262),(.125,-.257),(.124,-.253),
         (.132,-.205),(.135,-.196),(.136,-.192),(.136,-.187),(.135,-.183),
         (.145,-.119),(.147,-.112),(.147,-.106),(.143,-.102),
         (.139,-.106),(.139,-.114),(.129,-.185),(.117,-.255),(.108,-.315),(.103,-.323),(.001,-.323)]
lathe('Double wall metal pail',profile,steel)
for name,radius,z,thickness in [('Rolled mouth',.143,-.106,.006),('Rolled foot',.110,-.329,.0045)]:
    lathe(name,[(radius+thickness*math.cos(math.tau*j/16),z+thickness*math.sin(math.tau*j/16)) for j in range(17)],edge)
# Upright wire bail, with flat middle covered by a comfortable turned sleeve.
points=[]
for j in range(65):
    t=j/64;angle=math.pi*t
    height=.118+HANDLE_RISE
    points.append((.153*math.cos(angle),0,-height+height*math.sin(angle)**.55))
bail_parts=[tube('Round steel bail',points,.0045,edge,16)]
handle=lathe('Turned wooden grip',[(.001,-.052),(.014,-.052),(.018,-.046),(.019,-.035),(.020,0),(.019,.035),(.018,.046),(.014,.052),(.001,.052)],wood,64)
handle.rotation_euler.y=math.pi/2
bail_parts.append(handle)
for sign in [-1,1]:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=12,radius=1,location=(sign*.146,0,-.128))
    ear=bpy.context.object;ear.name='Stamped bail ear';ear.scale=(.006,.021,.024);ear.data.materials.append(steel);parts.append(ear)
    for face in ear.data.polygons:face.use_smooth=True
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=(sign*.152,0,-.126))
    rivet=bpy.context.object;rivet.name='Bail rivet';rivet.scale=(.004,.008,.008);rivet.data.materials.append(edge);parts.append(rivet)
    for face in rivet.data.polygons:face.use_smooth=True
equipment=[]
for name,objects,bone in [('Equipment.Bucket_Pail',[p for p in parts if p not in bail_parts],PAIL_BONE),
                          ('Equipment.Bucket_Bail',bail_parts,BONE)]:
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();obj=bpy.context.object
    obj.name=name;scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    if bone==PAIL_BONE:
        for vertex in obj.data.vertices:vertex.co.z-=HANDLE_RISE
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.012);bpy.ops.object.mode_set(mode='OBJECT')
    obj.data.calc_loop_triangles();equipment.append((obj,bone))
triangles=sum(len(obj.data.loop_triangles) for obj,bone in equipment)
bpy.ops.object.select_all(action='DESELECT')
for obj,bone in equipment:obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'Bucket.glb'),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
for obj,bone in equipment:
    group=obj.vertex_groups.new(name=bone);group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    mod=obj.modifiers.new('Rigid bucket binding','ARMATURE');mod.object=rig;obj.parent=rig


def orient(name,head,direction,reference):
    q=reference.to_quaternion();q=(q@Vector((0,1,0))).rotation_difference(direction.normalized())@q
    rig.pose.bones[name].matrix=Matrix.LocRotScale(head,q,Vector((1,1,1)));bpy.context.view_layer.update()


def arm(side,target,pail_pitch=0):
    sign=1 if side=='Left' else -1
    shoulder=rig.pose.bones[side+'Shoulder']
    orient(side+'Shoulder',shoulder.head.copy(),Vector((sign*.14,-.05,-.005)),rest[side+'Shoulder'])
    origin=rig.pose.bones[side+'Arm'].head.copy();delta=target.translation-origin;distance=delta.length
    a,b=[rig.data.bones[side+part].length for part in ['Arm','ForeArm']]
    assert abs(a-b)+.001<distance<a+b-.001,(scene.frame_current,side,distance,a+b)
    axis=delta.normalized();along=(a*a-b*b+distance*distance)/(2*distance)
    preferred=target.translation-(target.to_quaternion()@Vector((0,1,0)))*b
    pole_height=1.33+.12*max(0,min(1,(pail_pitch-35)/65)) if side=='Right' else 1.26
    pole=Vector((sign*.42,-.08,pole_height)).lerp(preferred,.88 if side=='Left' else .12)-origin
    pole=(pole-axis*pole.dot(axis)).normalized()
    elbow=origin+axis*along+pole*math.sqrt(max(0,a*a-along*along))
    # Keep the wrist and forearm's width axes aligned. The upper arm follows
    # the elbow hinge, so forearm pronation cannot collapse the wrist skin.
    width=target.to_quaternion() @ Vector((1,0,0))
    hinge=(elbow-origin).cross(target.translation-elbow).normalized()
    if side in previous_hinges:
        if hinge.dot(previous_hinges[side])<0:hinge=-hinge
    elif hinge.x>0:hinge=-hinge
    previous_hinges[side]=hinge.copy()
    for name,head,direction in [(side+'Arm',origin,elbow-origin),(side+'ForeArm',elbow,target.translation-elbow)]:
        axis=direction.normalized();across=(width-axis*width.dot(axis)).normalized()
        if name==side+'Arm':across=hinge
        q=Matrix((across,axis,across.cross(axis))).transposed().to_quaternion()
        rig.pose.bones[name].matrix=Matrix.LocRotScale(head,q,Vector((1,1,1)));bpy.context.view_layer.update()
    rig.pose.bones[side+'Hand'].matrix=target;bpy.context.view_layer.update()
    bend=math.degrees((target.translation-elbow).angle(target.to_quaternion()@Vector((0,1,0))))
    return {'reach':distance/(a+b),'elbow':list(elbow),'wrist':list(target.translation),'wrist_bend':bend}


# Explicit motion beats, in seconds: handle XYZ, bail pitch, pail pitch,
# left-hand contact amount, torso lean. Positive pail pitch tips AWAY from eyes.
READY=(-.22,-.48,1.57)
POSES={
    'Pour':[
        (0,READY,0,0,0,0),(.28,(-.16,-.40,1.55),0,0,.45,1),
        (.55,(-.08,-.42,1.64),-8,30,1,2),(.92,(-.06,-.47,1.56),-5,65,1,3),
        (1.22,(-.06,-.48,1.52),0,100,1,3),(1.65,(-.06,-.48,1.52),0,100,1,3),
        (2.08,(-.08,-.43,1.64),-8,30,1,2),(2.30,(-.14,-.40,1.55),0,0,.5,1),
        (2.8,READY,0,0,0,0)],
    'Scoop':[
        (0,READY,0,0,0,0),(.35,(-.14,-.40,1.56),0,5,.5,2),
        (.6,(-.06,-.43,1.64),-8,35,1,3),(.95,(-.06,-.52,1.47),-18,75,1,6),
        (1.25,(-.05,-.53,1.46),-15,55,1,6),(1.65,(-.07,-.43,1.64),-8,30,1,2),
        (1.9,(-.15,-.40,1.56),0,0,.5,1),(2.4,READY,0,0,0,0)]}


def channels(motion,time):
    rows=POSES[motion];values=[[*row[1],*row[2:]] for row in rows]
    def tangent(i,c):
        if i in (0,len(rows)-1):return 0.0
        a=(values[i][c]-values[i-1][c])/(rows[i][0]-rows[i-1][0])
        b=(values[i+1][c]-values[i][c])/(rows[i+1][0]-rows[i][0])
        return 2*a*b/(a+b) if a*b>0 else 0.0
    for i,(a,b) in enumerate(zip(rows,rows[1:])):
        if a[0]<=time<=b[0]+1e-8:
            dt=b[0]-a[0];t=(time-a[0])/dt
            return [(2*t**3-3*t*t+1)*values[i][c]+(t**3-2*t*t+t)*dt*tangent(i,c)
                    +(-2*t**3+3*t*t)*values[i+1][c]+(t**3-t*t)*dt*tangent(i+1,c) for c in range(7)]
    raise ValueError((motion,time))


# A palm under the rear-left quarter of the floor, fingers pointing diagonally
# inward. Once contact is established the hand stays fixed to the pail.
support_y=Vector((-.96,-.28,0)).normalized();support_z=Vector((0,0,-1))
support_q=Matrix((support_y.cross(support_z),support_y,support_z)).transposed().to_quaternion()
support=Matrix.LocRotScale(Vector((.175,.02,-.357-HANDLE_RISE)),support_q,Vector((1,1,1)))
rest_y=Vector((0,-.6,-.8));rest_x=Vector((1,0,0))
left_rest=Matrix.LocRotScale(Vector((.28,-.16,1.13)),Matrix((rest_x,rest_y,rest_x.cross(rest_y))).transposed().to_quaternion(),Vector((1,1,1)))


def left_fingers(contact):
    for finger,relaxed in [('Index',(18,24,12)),('Middle',(22,28,14)),
                           ('Ring',(26,32,16)),('Pinky',(30,36,18)),('Thumb',(12,18,10))]:
        for joint,angle in enumerate(relaxed,1):
            rig.pose.bones[f'LeftHand{finger}{joint}'].rotation_quaternion=Quaternion((1,0,0),-math.radians(angle))
    bpy.context.view_layer.update()
    hand_q=rig.pose.bones['LeftHand'].matrix.to_quaternion()
    for finger in ['Index','Middle','Ring','Pinky','Thumb']:
        for joint in [1,2,3]:
            bone=rig.pose.bones[f'LeftHand{finger}{joint}'];at=bone.matrix.copy();q=at.to_quaternion()
            # R11 rest fingers already curve. Zero local Euler flexion is not
            # a flat support palm: aim the actual phalanges along its plane.
            direction=Vector((0,1,0)) if finger!='Thumb' else Vector((.7,.7,0)).normalized()
            desired=(q@Vector((0,1,0))).rotation_difference(hand_q@direction)@q
            bone.matrix=Matrix.LocRotScale(at.translation,q.slerp(desired,contact),Vector((1,1,1)))
            bpy.context.view_layer.update()


# Fit the support to the deformed skin, not just bone centres. The upper skin
# of the flat palm touches the underside; fingers and thumb cannot poke through.
rig.pose.bones['LeftHand'].matrix=support;bpy.context.view_layer.update();left_fingers(1)
body=bpy.data.objects['Human_Body'];names={g.index:g.name for g in body.vertex_groups}
evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get());skin=evaluated.to_mesh()
assert len(skin.vertices)==len(body.data.vertices)
heights=[]
for vertex in body.data.vertices:
    if sum(g.weight for g in vertex.groups if names[g.group].startswith('LeftHand'))<.8:continue
    point=body.matrix_world@skin.vertices[vertex.index].co
    if math.hypot(point.x,point.y)<.108:heights.append(point.z)
evaluated.to_mesh_clear()
assert heights
support.translation.z+=(-.335-HANDLE_RISE-.001)-max(heights)


actions={};records={}
for motion,duration in DURATIONS.items():
    previous_hinges={};previous_rotations={}
    action=bpy.data.actions.new('FP_Bucket_'+motion);action.use_fake_user=True
    rig.animation_data_create();rig.animation_data.action=action
    count=round(duration*FPS);records[motion]=[]
    for frame in range(count+1):
        scene.frame_set(frame)
        for bone in rig.pose.bones:
            bone.rotation_mode='QUATERNION';bone.matrix_basis=fingers.get(bone.name,neutral[bone.name])
            if motion in gaits and any(part in bone.name for part in ['UpLeg','Leg','Foot','Toe']):bone.matrix_basis=gaits[motion][frame][bone.name]
        bpy.context.view_layer.update()
        phase=frame/count*math.tau
        anchor=Vector(READY);pitch=0.0;roll=0.0;pail_pitch=0.0;contact=0.0;lean=0.0
        if motion in ['Walk','Run']:
            strength=1 if motion=='Walk' else 1.45
            anchor+=Vector((.009*math.sin(phase),.007*math.sin(phase),.012*math.cos(2*phase)))*strength
            pitch+=1.2*math.sin(phase)*strength;roll=1.2*math.sin(phase)*strength
        elif motion=='Jump':anchor.z-=.018*math.sin(phase*.5)**2
        elif motion in POSES:
            data=channels(motion,frame/FPS);anchor=Vector(data[:3]);pitch,pail_pitch,contact,lean=data[3:]
        for name in ['Spine','Spine1','Spine2']:
            at=rig.pose.bones[name].matrix.copy()
            rig.pose.bones[name].matrix=Matrix.LocRotScale(at.translation,Quaternion((1,0,0),math.radians(lean/3))@at.to_quaternion(),Vector((1,1,1)))
            bpy.context.view_layer.update()
        at=rig.pose.bones['Neck'].matrix.copy()
        rig.pose.bones['Neck'].matrix=Matrix.LocRotScale(at.translation,Quaternion((1,0,0),math.radians(-lean))@at.to_quaternion(),Vector((1,1,1)))
        bpy.context.view_layer.update()
        yaw=Quaternion((0,0,1),math.radians(20))
        rotation=yaw@Quaternion((0,1,0),math.radians(roll))@Quaternion((1,0,0),math.radians(pitch))
        tool=Matrix.LocRotScale(anchor,rotation,Vector((1,1,1)))
        # Bail and pail rotate independently around the two existing ear pivots.
        pail_q=yaw@Quaternion((0,1,0),math.radians(roll))@Quaternion((1,0,0),math.radians(pail_pitch))
        pail=Matrix.LocRotScale(tool@HINGE-pail_q@HINGE,pail_q,Vector((1,1,1)))
        rig.pose.bones[BONE].matrix=tool;bpy.context.view_layer.update()
        rig.pose.bones[PAIL_BONE].matrix=pail;bpy.context.view_layer.update()
        arms={'Right':arm('Right',tool@grip,pail_pitch)}
        left_target=left_rest.lerp(pail@support,contact)
        arms['Left']=arm('Left',left_target)
        left_fingers(contact)
        for bone in rig.pose.bones:
            if bone.name in previous_rotations and bone.rotation_quaternion.dot(previous_rotations[bone.name])<0:
                bone.rotation_quaternion.negate()
            previous_rotations[bone.name]=bone.rotation_quaternion.copy()
            bone.keyframe_insert('location',frame=frame,group=bone.name)
            bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
            bone.keyframe_insert('scale',frame=frame,group=bone.name)
        records[motion].append({'frame':frame,'arms':arms,'pivot':list(anchor),'pail_pitch':pail_pitch,'bail_pitch':pitch,'left_contact':contact})
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    action.use_frame_range=True;action.frame_start=0;action.frame_end=count;actions[motion]=action
scene.render.fps=FPS;scene.frame_start=0;scene.frame_end=60
rig.animation_data.action=actions['Idle']
if actions['Idle'].slots:rig.animation_data.action_slot=actions['Idle'].slots[0]
scene.frame_set(0)
rig['bucket_description']='Revision 2: overhand carry, independent ear hinge, left palm supports pail; authored dip/lift and supported pour/hold/recovery. Earlier hands and gestures rejected. Appearance review pending.'
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.data.objects['Human_Body'].select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.bucket.glb'),export_format='GLB',use_selection=True,export_materials='NONE',export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_skins=True,export_morph=False,export_yup=True)
report={'status':'Previous hands/use rejected; revision 2 awaiting review','source':str(source.relative_to(ROOT)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'neutral_source':'addons/characters/authoring/Human.unarmed.blend','neutral_source_sha256':hashlib.sha256((OUT/'Human.unarmed.blend').read_bytes()).hexdigest(),'triangles':triangles,'vertices':sum(len(obj.data.vertices) for obj,bone in equipment),'fps':FPS,'durations':DURATIONS,'grip_matrix':[list(row) for row in grip],'support_matrix':[list(row) for row in support],'poses':POSES,'samples':records}
(OUT/'Human.bucket.json').write_text(json.dumps(report,indent=2))
for obj in bpy.data.objects:
    if obj.type=='MESH' and obj.name.startswith('Equipment.') and obj not in [entry[0] for entry in equipment]:
        obj.hide_render=True;obj.hide_set(True)
scene.timeline_markers.clear()
for label,frame in [('OVERHAND CARRY',0),('SUPPORT CONTACT',33),('TIP AWAY',55),('POUR HOLD',74),('UPRIGHT',125),('RELEASE / RECOVER',138),('CARRY',168)]:scene.timeline_markers.new(label,frame=frame)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.bucket.blend'),compress=True)
print('BUCKET_AUTHORED',triangles,'triangles;',DURATIONS)
