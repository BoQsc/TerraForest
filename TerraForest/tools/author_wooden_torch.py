# SPDX-License-Identifier: 0BSD
"""Run in Blender against the preserved Human.r11.blend. Original torch art.

Packed PBR images, editable geometry, fixed grip and restrained carry actions.
Fire is a separate runtime effect; it never modifies the character skeleton.
"""
import hashlib
import json
import math
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'addons/characters/authoring'
ASSETS=ROOT/'addons/characters/runtime/assets'
source=Path(bpy.data.filepath)
assert source.name=='Human.r11.blend'
rig=bpy.data.objects['Human_Rig'];scene=bpy.context.scene
sys.path.insert(0,str(ROOT/'tools'))
from unarmed_hand_weights import repair_hand
for side in ['Left','Right']:repair_hand(bpy.data.objects['Human_Body'],rig,side)
FPS=60
DURATIONS={'Idle':3.0,'Walk':1.0,'Run':.8,'Jump':1.5,'Equip':.45}
BONE='Weapon_Axe'

def sample(action,frame):
    rig.animation_data_create();rig.animation_data.action=action
    if action.slots:rig.animation_data.action_slot=action.slots[0]
    scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
    return {b.name:b.matrix_basis.copy() for b in rig.pose.bones}

base=sample(bpy.data.actions['FP_Axe_Idle'],1)
grip=rig.pose.bones[BONE].matrix.inverted()@rig.pose.bones['RightHand'].matrix
grip.translation.z=0
fingers={n:m for n,m in base.items() if 'RightHand' in n and n!='RightHand'}
with bpy.data.libraries.load(str(OUT/'Human.unarmed.blend'),link=False) as (_,loaded):
    loaded.actions=['FP_Unarmed_Idle']
neutral=sample(bpy.data.actions['FP_Unarmed_Idle'],0)
from torch_hand_pose import fit_grip
grip,fingers,grip_fit=fit_grip(rig,bpy.data.objects['Human_Body'],grip,fingers)
# Put the wrist behind the shaft, in line with the forearm. The old axe-facing
# orientation put it beside the shaft and forced a 105-degree sideways bend.
grip=Matrix.Rotation(math.pi/2,4,'Z')@grip
gaits={}
for motion in ['Walk','Run','Jump']:
    action=bpy.data.actions[motion];start,end=action.frame_range;count=round(DURATIONS[motion]*FPS)
    gaits[motion]=[sample(action,start+(end-start)*i/count) for i in range(count+1)]
    if motion!='Jump':gaits[motion][-1]=gaits[motion][0]
for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type=='MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            if key.name!='Basis':key.value=0
for action in list(bpy.data.actions):bpy.data.actions.remove(action)
for bone in rig.pose.bones:bone.rotation_mode='QUATERNION';bone.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
rest={b.name:b.matrix.copy() for b in rig.pose.bones}

def material(name,kind):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value=.84
    size=1024;y,x=np.mgrid[0:size,0:size].astype(np.float32)/size
    rng=np.random.default_rng(816+kind);noise=rng.normal(0,1,(size,size)).astype(np.float32)
    if kind==0:
        # Lengthwise fibres and subtle raised grain on the peeled shaft.
        grain=np.sin(x*277+np.sin(y*13)*2+np.sin(x*21+y*7)*3)
        broad=np.sin(x*47+np.sin(y*11)*1.4)
        fissure=np.clip((np.sin(x*633+np.sin(y*5)*3)-.94)*15,0,1)
        color=np.clip(np.array([.34,.20,.09])*(1+grain[...,None]*.16+broad[...,None]*.18-fissure[...,None]*.35),0,1)
        height=grain*.001+broad*.002-fissure*.002;rough=.76+grain*.06
    else:
        weave=np.sin(x*math.tau*192)*np.sin(y*math.tau*192)
        soot=np.clip((y-.35)*1.7,0,.9)
        stains=(np.sin(x*33+y*21)*np.sin(y*41-x*13)+1)*.12
        tint=np.array([.58,.43,.26]) if kind==1 else np.array([.045,.026,.015])
        color=np.clip(tint*(1-soot[...,None]*.7-stains[...,None]+weave[...,None]*.14+noise[...,None]*.035),0,1)
        height=weave*.0007+noise*.0002;rough=.88+weave*.04
    dy,dx=np.gradient(height)
    normal=np.stack((-dx*230,-dy*230,np.ones_like(dx)),axis=-1)
    normal=normal/np.linalg.norm(normal,axis=-1,keepdims=True)*.5+.5
    for label,pixels,space in [('BaseColor',color,'sRGB'),('Roughness',np.repeat(np.clip(rough,0,1)[...,None],3,axis=-1),'Non-Color'),('Normal',normal,'Non-Color')]:
        image=bpy.data.images.new(name+'.'+label,width=size,height=size,alpha=False);image.colorspace_settings.name=space
        rgba=np.ones((size,size,4),dtype=np.float32);rgba[:,:,:3]=pixels
        image.pixels.foreach_set(rgba.ravel());image.update();image.pack()
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
        if label=='Normal':
            bump=mat.node_tree.nodes.new('ShaderNodeNormalMap');bump.inputs['Strength'].default_value=.55
            mat.node_tree.links.new(node.outputs['Color'],bump.inputs['Color']);mat.node_tree.links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
        else:mat.node_tree.links.new(node.outputs['Color'],bsdf.inputs['Base Color' if label=='BaseColor' else 'Roughness'])
    return mat

wood=material('Torch.Peeled weathered wood',0)
cloth=material('Torch.Resin soaked linen',1)
char=material('Torch.Charred crown',2)
parts=[]
def mesh(name,vertices,faces,uvs,mat):
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
    obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);data.materials.append(mat)
    layer=data.uv_layers.new()
    for face in data.polygons:
        face.use_smooth=True
        for loop in face.loop_indices:layer.data[loop].uv=uvs[data.loops[loop].vertex_index]
    parts.append(obj);return obj

def sleeve(name,z0,z1,radius,mat,rows=48,segments=64,bulge=0):
    vertices=[];uv=[];faces=[]
    for i in range(rows+1):
        v=i/rows;z=z0+(z1-z0)*v
        for j in range(segments+1):
            u=j/segments;a=u*math.tau
            r=radius+bulge*math.sin(math.pi*v)**.6
            r*=1+.035*math.sin(a*5+v*3)+.022*math.sin(a*9-v*7)
            cx=.003*math.sin(z*7);cy=.002*math.sin(z*11)
            vertices.append((cx+r*math.cos(a),cy+r*math.sin(a),z));uv.append((u,v))
    for i in range(rows):
        for j in range(segments):
            a=i*(segments+1)+j;faces.append((a,a+1,a+segments+2,a+segments+1))
    faces.extend([tuple(reversed(range(segments))),tuple(rows*(segments+1)+j for j in range(segments))])
    return mesh(name,vertices,faces,uv,mat)

sleeve('Hand shaped ash shaft',-.22,.455,.0205,wood,64,64,.001)
sleeve('Bound linen core',.235,.445,.032,cloth,40,64,.016)
# Overlapping helical strips, with actual rolled edges rather than painted rings.
vertices=[];uv=[];faces=[];steps=512;across=10
for i in range(steps+1):
    t=i/steps;a=t*math.tau*6.5
    for j in range(across+1):
        v=j/across;z=.244+t*.183+(v-.5)*.036
        envelope=math.sin(math.pi*max(0,min(1,(z-.235)/.21)))**.6
        r=.036+.016*envelope+.0015*math.sin(v*math.pi)+.001*math.cos(a*3)
        vertices.append((r*math.cos(a),r*math.sin(a),z));uv.append((v,t))
for i in range(steps):
    for j in range(across):
        a=i*(across+1)+j;faces.append((a,a+across+1,a+across+2,a+1))
ribbon=mesh('Overlapping linen winding',vertices,faces,uv,cloth)
solid=ribbon.modifiers.new('Linen thickness','SOLIDIFY');solid.thickness=.0012
bpy.context.view_layer.objects.active=ribbon;ribbon.select_set(True);bpy.ops.object.modifier_apply(modifier=solid.name)
sleeve('Blackened split crown',.405,.463,.033,char,18,64,.012)
# Short charred splinters form an irregular crown below the fire.
for k in range(9):
    a=k*math.tau/9
    obj=sleeve('Charred fibre '+str(k),.427,.473+.008*math.sin(k*4),.006,char,6,12,.002)
    obj.location=(.027*math.cos(a),.027*math.sin(a),0)
bpy.ops.object.select_all(action='DESELECT')
for obj in parts:obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();equipment=bpy.context.object
equipment.name='Equipment.Torch';scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
for vertex in equipment.data.vertices:
    if vertex.co.z>0:vertex.co.z*=.80
equipment.data.calc_loop_triangles();triangles=len(equipment.data.loop_triangles)
bpy.ops.export_scene.gltf(filepath=str(ASSETS/'Torch.glb'),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
group=equipment.vertex_groups.new(name=BONE);group.add(list(range(len(equipment.data.vertices))),1,'REPLACE')
mod=equipment.modifiers.new('Rigid torch binding','ARMATURE');mod.object=rig;equipment.parent=rig

def orient(name,head,direction,reference):
    q=reference.to_quaternion();q=(q@Vector((0,1,0))).rotation_difference(direction.normalized())@q
    rig.pose.bones[name].matrix=Matrix.LocRotScale(head,q,Vector((1,1,1)));bpy.context.view_layer.update()

def arm(side,target):
    sign=1 if side=='Left' else -1
    shoulder=rig.pose.bones[side+'Shoulder']
    orient(side+'Shoulder',shoulder.head.copy(),Vector((sign*.14,-.05,-.005)),rest[side+'Shoulder'])
    origin=rig.pose.bones[side+'Arm'].head.copy();delta=target.translation-origin;distance=delta.length
    a,b=[rig.data.bones[side+part].length for part in ['Arm','ForeArm']]
    assert abs(a-b)+.001<distance<a+b-.001,(distance,a+b)
    axis=delta.normalized();along=(a*a-b*b+distance*distance)/(2*distance)
    # Choose the reachable elbow nearest a straight wrist, with a small natural
    # outward bias. Solve and key both arms at every frame, not just endpoints.
    preferred=target.translation-(target.to_quaternion()@Vector((0,1,0)))*b
    pole=Vector((sign*.42,-.05,1.23)).lerp(preferred,.90)-origin
    pole=(pole-axis*pole.dot(axis)).normalized()
    elbow=origin+axis*along+pole*math.sqrt(max(0,a*a-along*along))
    width=target.to_quaternion()@Vector((1,0,0));hinge=(elbow-origin).cross(target.translation-elbow).normalized()
    # Keep the same elbow-frame handedness through the whole raise. Choosing
    # its sign from world X flips 180 degrees as the elbow crosses that plane.
    if side=='Left':hinge=-hinge
    for name,head,direction in [(side+'Arm',origin,elbow-origin),(side+'ForeArm',elbow,target.translation-elbow)]:
        axis=direction.normalized();across=(width-axis*width.dot(axis)).normalized()
        if name==side+'Arm':across=hinge
        q=Matrix((across,axis,across.cross(axis))).transposed().to_quaternion()
        rig.pose.bones[name].matrix=Matrix.LocRotScale(head,q,Vector((1,1,1)));bpy.context.view_layer.update()
    rig.pose.bones[side+'Hand'].matrix=target;bpy.context.view_layer.update()
    bend=math.degrees((target.translation-elbow).angle(target.to_quaternion()@Vector((0,1,0))))
    return {'reach_fraction':distance/(a+b),'wrist_bend':bend,'elbow':list(elbow),'wrist':list(target.translation)}

def relaxed_left_fingers():
    # R11's rest fingers already curve. Aim the actual phalanges into a gentle
    # relaxed arc instead of adding another set of fist-like local rotations.
    hand=rig.pose.bones['LeftHand'].matrix.to_quaternion()
    for finger,curls in [('Index',(8,18,27)),('Middle',(11,23,34)),('Ring',(15,28,40)),('Pinky',(19,33,46)),('Thumb',(6,15,25))]:
        for joint,angle in enumerate(curls,1):
            bone=rig.pose.bones[f'LeftHand{finger}{joint}'];at=bone.matrix.copy();q=at.to_quaternion()
            direction=Vector((0,math.cos(math.radians(angle)),-math.sin(math.radians(angle))))
            if finger=='Thumb':direction=Vector((.45,.87,-.10-joint*.04)).normalized()
            desired=(q@Vector((0,1,0))).rotation_difference(hand@direction)@q
            bone.matrix=Matrix.LocRotScale(at.translation,desired,Vector((1,1,1)));bpy.context.view_layer.update()

actions={};records={}
for motion,duration in DURATIONS.items():
    action=bpy.data.actions.new('FP_Torch_'+motion);action.use_fake_user=True
    rig.animation_data_create();rig.animation_data.action=action;count=round(duration*FPS)
    previous={};max_reach=0;frame_records=[]
    for frame in range(count+1):
        scene.frame_set(frame)
        for bone in rig.pose.bones:
            bone.rotation_mode='QUATERNION';bone.matrix_basis=fingers.get(bone.name,neutral[bone.name])
            if motion in gaits and any(part in bone.name for part in ['UpLeg','Leg','Foot','Toe']):bone.matrix_basis=gaits[motion][frame][bone.name]
        bpy.context.view_layer.update();phase=frame/count*math.tau
        at=Vector((-.29,-.43,1.37));pitch=9.;roll=-7.
        if motion=='Idle':at.z+=.002*math.sin(phase)
        elif motion in ['Walk','Run']:
            strength=1 if motion=='Walk' else 1.6
            at+=Vector((.007*math.sin(phase),.008*math.sin(phase),.009*math.cos(2*phase)))*strength
            pitch+=1.5*math.sin(phase)*strength;roll+=1.2*math.sin(phase)*strength
        elif motion=='Jump':at.z-=.025*math.sin(phase*.5)**2
        elif motion=='Equip':
            t=frame/count;t=t*t*(3-2*t)
            at=Vector((-.30,-.24,1.13)).lerp(at,t);pitch=65+(pitch-65)*t
        q=Quaternion((0,1,0),math.radians(roll))@Quaternion((1,0,0),math.radians(pitch))
        tool=Matrix.LocRotScale(at,q,Vector((1,1,1)))
        rig.pose.bones[BONE].matrix=tool;bpy.context.view_layer.update()
        right=arm('Right',tool@grip);max_reach=max(max_reach,right['reach_fraction'])
        left_y=Vector((0,-.2,-.98)).normalized();left_x=Vector((-1,0,0))
        left=Matrix.LocRotScale(Vector((.28,-.16,1.13)),Matrix((left_x,left_y,left_x.cross(left_y))).transposed().to_quaternion(),Vector((1,1,1)))
        left_arm=arm('Left',left);relaxed_left_fingers()
        frame_records.append({'frame':frame,'Right':right,'Left':left_arm})
        for bone in rig.pose.bones:
            if bone.name in previous and bone.rotation_quaternion.dot(previous[bone.name])<0:bone.rotation_quaternion.negate()
            previous[bone.name]=bone.rotation_quaternion.copy()
            for prop in ['location','rotation_quaternion','scale']:bone.keyframe_insert(prop,frame=frame,group=bone.name)
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    action.use_frame_range=True;action.frame_start=0;action.frame_end=count;actions[motion]=action
    records[motion]={'seconds':duration,'frames':count,'max_reach_fraction':max_reach,'samples':frame_records}
scene.render.fps=FPS;scene.frame_start=0;scene.frame_end=180
rig.animation_data.action=actions['Idle']
if actions['Idle'].slots:rig.animation_data.action_slot=actions['Idle'].slots[0]
scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.data.objects['Human_Body'].select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.torch.glb'),export_format='GLB',use_selection=True,export_materials='NONE',export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_skins=True,export_morph=False,export_yup=True)
for obj in bpy.data.objects:
    if obj.type=='MESH' and obj.name.startswith('Equipment.') and obj!=equipment:obj.hide_render=True;obj.hide_set(True)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.torch.blend'),compress=True)
(OUT/'Human.torch.json').write_text(json.dumps({'status':'Hands reauthored after rejection; visual approval pending','source':str(source.relative_to(ROOT)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'triangles':triangles,'vertices':len(equipment.data.vertices),'fps':FPS,'actions':records,'grip':[list(row) for row in grip],'grip_fit':grip_fit},indent=2)+'\n')
print('TORCH_AUTHORED',triangles,'triangles; grip fit:',grip_fit)
