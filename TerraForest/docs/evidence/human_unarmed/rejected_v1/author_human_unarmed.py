# SPDX-License-Identifier: 0BSD
"""Author a neutral empty-hand hold and a straight right punch on the R11 rig."""
import hashlib
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'addons/characters/authoring'
source = Path(bpy.data.filepath)
assert source.name == 'Human.r11.blend'
rig = bpy.data.objects['Human_Rig']; scene = bpy.context.scene
FPS, END, CONTACT = 60, 48, 18
idle = bpy.data.actions['Idle']; rig.animation_data.action = idle
if idle.slots: rig.animation_data.action_slot = idle.slots[0]
scene.frame_set(1); bpy.context.view_layer.update()
base = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
reference = {b.name: b.matrix.copy() for b in rig.pose.bones}
for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type == 'MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            if key.name != 'Basis': key.value = 0
for action in list(bpy.data.actions): bpy.data.actions.remove(action)
for bone in rig.pose.bones: bone.rotation_mode = 'QUATERNION'

# Frame, right wrist XYZ, fist closure, pronation roll, upper torso yaw.
# Contact keeps a small elbow bend, with no joint stretching or root movement.
POSES = [
    (0,  (-.270, -.350, 1.350), 0.0, 70,  0),
    (6,  (-.270, -.290, 1.335), 1.0, 62, -2),
    (10, (-.235, -.345, 1.410), 1.0, 40,  0),
    (18, (-.095, -.435, 1.500), 1.0,  4,  5),
    (20, (-.108, -.422, 1.487), 1.0,  8,  4),
    (29, (-.245, -.300, 1.335), 1.0, 58,  0),
    (40, (-.270, -.350, 1.350), 0.0, 70,  0),
    (48, (-.270, -.350, 1.350), 0.0, 70,  0),
]

def channels(frame):
    values = [[*p[1], *p[2:]] for p in POSES]
    def tangent(i, c):
        if i in (0, len(POSES)-1): return 0
        a = (values[i][c]-values[i-1][c])/(POSES[i][0]-POSES[i-1][0])
        b = (values[i+1][c]-values[i][c])/(POSES[i+1][0]-POSES[i][0])
        return 2*a*b/(a+b) if a*b > 0 else 0
    for i, (a, b) in enumerate(zip(POSES, POSES[1:])):
        if a[0] <= frame <= b[0]:
            dt = b[0]-a[0]; t = (frame-a[0])/dt
            return [(2*t**3-3*t*t+1)*values[i][c]+(t**3-2*t*t+t)*dt*tangent(i,c)
                    +(-2*t**3+3*t*t)*values[i+1][c]+(t**3-t*t)*dt*tangent(i+1,c) for c in range(6)]
    raise ValueError(frame)

def orient(name, head, direction):
    old = reference[name].to_quaternion()
    q = (old @ Vector((0,1,0))).rotation_difference(direction.normalized()) @ old
    rig.pose.bones[name].matrix = Matrix.LocRotScale(head, q, Vector((1,1,1)))
    bpy.context.view_layer.update()

def arm(side, wrist, roll):
    sign = 1 if side == 'Left' else -1
    shoulder = rig.pose.bones[side+'Shoulder'].head.copy()
    orient(side+'Shoulder', shoulder, Vector((sign*.14,-.050,-.010)))
    origin = rig.pose.bones[side+'Arm'].head.copy()
    delta = wrist-origin; distance = delta.length; axis = delta.normalized()
    a, b = [rig.data.bones[side+n].length for n in ['Arm','ForeArm']]
    assert abs(a-b)+.001 < distance < a+b-.004, (scene.frame_current, side, distance, a+b)
    along = (a*a-b*b+distance*distance)/(2*distance)
    pole = Vector((sign*.40,-.08,1.05))-origin
    pole = (pole-axis*pole.dot(axis)).normalized()
    elbow = origin + axis*along + pole*math.sqrt(max(0,a*a-along*along))
    y = (wrist-elbow).normalized()
    x = Vector((sign,0,0)); x = (x-y*x.dot(y)).normalized()
    z = x.cross(y).normalized()
    q = Quaternion(y, math.radians(roll)) @ Matrix((x,y,z)).transposed().to_quaternion()
    # Distribute forearm pronation through the bones instead of twisting the
    # hand relative to a separately oriented forearm (which collapses the skin).
    width = q @ Vector((1,0,0))
    for name, head, direction in [(side+'Arm',origin,elbow-origin),(side+'ForeArm',elbow,wrist-elbow)]:
        axis = direction.normalized(); across = (width-axis*width.dot(axis)).normalized()
        rotation = Matrix((across,axis,across.cross(axis))).transposed().to_quaternion()
        rig.pose.bones[name].matrix = Matrix.LocRotScale(head,rotation,Vector((1,1,1)))
        bpy.context.view_layer.update()
    rig.pose.bones[side+'Hand'].matrix = Matrix.LocRotScale(wrist,q,Vector((1,1,1)))
    bpy.context.view_layer.update()
    return {'reach':distance/(a+b),'elbow':list(elbow),'wrist':list(wrist),
            'endpoint_error':(rig.pose.bones[side+'Hand'].head-wrist).length}

def fingers(side, closure):
    for finger, relaxed, closed in [
        ('Index',(12,18,8),(64,84,50)), ('Middle',(16,22,10),(68,88,54)),
        ('Ring',(20,26,12),(70,88,54)), ('Pinky',(24,30,16),(72,86,52)),
        ('Thumb',(12,18,10),(8,25,20))]:
        for joint, (a,b) in enumerate(zip(relaxed,closed),1):
            rig.pose.bones[f'{side}Hand{finger}{joint}'].rotation_quaternion = Quaternion((1,0,0),-math.radians(a+(b-a)*closure))

def close_thumb(closure):
    # Oppose the thumb across the outside of the folded index/middle fingers.
    # Pure hinge flexion would leave the thumb dangling below the fist.
    hand = rig.pose.bones['RightHand'].matrix.to_quaternion()
    for name, direction in [('RightHandThumb2',(.80,.45,-.35)),('RightHandThumb3',(.93,.13,-.34))]:
        bone = rig.pose.bones[name]; at = bone.matrix.copy(); original = at.to_quaternion()
        desired = (original @ Vector((0,1,0))).rotation_difference((hand @ Vector(direction)).normalized()) @ original
        bone.matrix = Matrix.LocRotScale(at.translation,original.slerp(desired,closure),Vector((1,1,1)))
        bpy.context.view_layer.update()

def pose(frame):
    for b in rig.pose.bones: b.matrix_basis = base[b.name]
    bpy.context.view_layer.update()
    data = channels(frame); wrist = Vector(data[:3]); closure, roll, yaw = data[3:]
    for name in ['Spine','Spine1','Spine2']:
        bone = rig.pose.bones[name]; at = bone.matrix.copy()
        bone.matrix = Matrix.LocRotScale(at.translation, Quaternion((0,0,1),math.radians(yaw/3)) @ at.to_quaternion(),Vector((1,1,1)))
        bpy.context.view_layer.update()
    neck = rig.pose.bones['Neck']; at = neck.matrix.copy()
    neck.matrix = Matrix.LocRotScale(at.translation,Quaternion((0,0,1),math.radians(-yaw)) @ at.to_quaternion(),Vector((1,1,1)))
    bpy.context.view_layer.update()
    arms = {'Right':arm('Right',wrist,roll), 'Left':arm('Left',Vector((.27,-.35,1.35)),70)}
    fingers('Right',closure); fingers('Left',0)
    bpy.data.objects['Human_Body'].data.shape_keys.key_blocks['TP_Grip_Right_Closed'].value = closure
    bpy.context.view_layer.update()
    close_thumb(closure)
    return {'frame':frame,'closure':closure,'roll':roll,'torso_yaw':yaw,'arms':arms,
            'knuckle':list(rig.pose.bones['RightHandMiddle1'].head)}

actions = {}; corrective_actions = {}; samples = []
body_keys = bpy.data.objects['Human_Body'].data.shape_keys
for suffix, end in [('Idle',120),('Punch',END)]:
    action = bpy.data.actions.new('FP_Unarmed_'+suffix)
    rig.animation_data_create(); rig.animation_data.action = action; action.use_fake_user = True
    corrective = bpy.data.actions.new('FP_Unarmed_'+suffix+'__Body_Correctives')
    corrective.use_fake_user = True; body_keys.animation_data_create(); body_keys.animation_data.action = corrective
    for frame in (range(end+1) if suffix == 'Punch' else [0,end]):
        scene.frame_set(frame); record = pose(frame if suffix == 'Punch' else 0)
        for bone in rig.pose.bones:
            for path in ['location','rotation_quaternion','scale']: bone.keyframe_insert(path,frame=frame,group=bone.name)
        body_keys.key_blocks['TP_Grip_Right_Closed'].keyframe_insert('value',frame=frame)
        if suffix == 'Punch': samples.append(record)
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points: key.interpolation = 'LINEAR'
    action.use_frame_range = True; action.frame_start = 0; action.frame_end = end; actions[suffix] = action
    corrective_actions[suffix] = corrective
scene.render.fps = FPS; scene.frame_start = 0; scene.frame_end = END
scene.timeline_markers.clear()
for title, frame in [('NEUTRAL',0),('FIST CLOSED',6),('CONTACT',CONTACT),('WITHDRAW',29),('RELAX',40)]: scene.timeline_markers.new(title,frame=frame)
rig.animation_data.action = actions['Punch']
if actions['Punch'].slots: rig.animation_data.action_slot = actions['Punch'].slots[0]
body_keys.animation_data.action = corrective_actions['Punch']
if corrective_actions['Punch'].slots: body_keys.animation_data.action_slot = corrective_actions['Punch'].slots[0]
scene.frame_set(0)
rig['unarmed_description'] = 'Neutral low relaxed hands; right straight punch closes before extension, pronates through contact, retracts and relaxes. Root and feet stay fixed. No gameplay event tracks.'
for obj in bpy.data.objects:
    if obj.type == 'MESH': obj.hide_render = obj.name.startswith(('Equipment.','Hair.','Brows.','Eye'))
bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True); bpy.data.objects['Human_Body'].select_set(True); bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.unarmed.glb'),export_format='GLB',use_selection=True,
    export_materials='NONE',export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,
    export_force_sampling=True,export_skins=True,export_morph=False,export_yup=True)
report = {'status':'Implemented; user appearance review pending','source':str(source.relative_to(ROOT)),
          'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'fps':FPS,'duration':END/FPS,'contact_frame':CONTACT,
          'poses':POSES,'samples':samples}
(OUT/'Human.unarmed.json').write_text(json.dumps(report,indent=2))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.unarmed.blend'),compress=True)
print('UNARMED_AUTHORED',json.dumps({k:v for k,v in report.items() if k not in ['poses','samples']}))
