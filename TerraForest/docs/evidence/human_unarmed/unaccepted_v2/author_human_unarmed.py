# SPDX-License-Identifier: 0BSD
"""Author a neutral empty-hand hold and a straight right punch on the R11 rig."""
import hashlib
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'addons/characters/authoring'
source = Path(bpy.data.filepath)
assert source.name == 'Human.r11.blend'
rig = bpy.data.objects['Human_Rig']; scene = bpy.context.scene
sys.path.insert(0,str(ROOT/'tools'))
from unarmed_hand_weights import repair_hand
hand_repair = repair_hand(bpy.data.objects['Human_Body'],rig,'Right')
left_repair = repair_hand(bpy.data.objects['Human_Body'],rig,'Left')
hand_repair['vertices'] += left_repair['vertices']
hand_repair['counts'] = {'Right':hand_repair['counts'],'Left':left_repair['counts']}
hand_repair['cross_finger_vertices_before'] += left_repair['cross_finger_vertices_before']
(OUT/'Human.unarmed.weights.json').write_text(json.dumps(hand_repair,indent=2))
FPS, END, CONTACT = 60, 54, 18
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
    (7,  (-.250, -.245, 1.455), 1.0, 76, -2),
    (11, (-.235, -.245, 1.495), 1.0, 78, -2),
    (14, (-.205, -.310, 1.535), 1.0, 66,  1),
    (16, (-.145, -.398, 1.565), 1.0, 28,  5),
    (18, (-.075, -.462, 1.580), 1.0,  5,  8),
    (20, (-.115, -.408, 1.565), 1.0, 18,  6),
    (25, (-.225, -.250, 1.495), 1.0, 72,  0),
    (32, (-.250, -.245, 1.455), 1.0, 76, -1),
    (44, (-.270, -.350, 1.350), 0.0, 70,  0),
    (54, (-.270, -.350, 1.350), 0.0, 70,  0),
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
    # Both hands share the palm-down reference basis. The left finger rest
    # coordinates already mirror the right; flipping this axis inverts its palm.
    x = Vector((-1,0,0)); x = (x-y*x.dot(y)).normalized()
    z = x.cross(y).normalized()
    q = Quaternion(y, math.radians(roll)) @ Matrix((x,y,z)).transposed().to_quaternion()
    # Distribute forearm pronation through the bones instead of twisting the
    # hand relative to a separately oriented forearm (which collapses the skin).
    width = q @ Vector((1,0,0))
    upper_axis = (elbow-origin).normalized(); lower_axis = (wrist-elbow).normalized()
    hinge = upper_axis.cross(lower_axis).normalized()
    if hinge.dot(width)<0: hinge = -hinge
    for name, head, direction in [(side+'Arm',origin,elbow-origin),(side+'ForeArm',elbow,wrist-elbow)]:
        axis = direction.normalized(); across = (width-axis*width.dot(axis)).normalized()
        if name.endswith('Arm') and not name.endswith('ForeArm'): across = hinge
        rotation = Matrix((across,axis,across.cross(axis))).transposed().to_quaternion()
        rig.pose.bones[name].matrix = Matrix.LocRotScale(head,rotation,Vector((1,1,1)))
        bpy.context.view_layer.update()
    rig.pose.bones[side+'Hand'].matrix = Matrix.LocRotScale(wrist,q,Vector((1,1,1)))
    bpy.context.view_layer.update()
    return {'reach':distance/(a+b),'elbow':list(elbow),'wrist':list(wrist),
            'endpoint_error':(rig.pose.bones[side+'Hand'].head-wrist).length}

def fingers(side, closure):
    for finger, relaxed, closed in [
        ('Index',(12,18,8),(78,94,46)), ('Middle',(16,22,10),(82,92,46)),
        ('Ring',(20,26,12),(84,92,46)), ('Pinky',(24,30,16),(86,90,44)),
        ('Thumb',(12,18,10),(8,25,20))]:
        for joint, (a,b) in enumerate(zip(relaxed,closed),1):
            rig.pose.bones[f'{side}Hand{finger}{joint}'].rotation_quaternion = Quaternion((1,0,0),-math.radians(a+(b-a)*closure))

def close_thumb(side, closure):
    # Oppose the thumb across the outside of the folded index/middle fingers.
    # Pure hinge flexion would leave the thumb dangling below the fist.
    hand_matrix = rig.pose.bones[side+'Hand'].matrix
    hand = hand_matrix.to_quaternion()
    sign = -1 if (hand_matrix.inverted() @ rig.pose.bones[side+'HandThumb1'].head).x < 0 else 1
    for name, direction in [(side+'HandThumb1',(sign*.20,.93,-.30)),(side+'HandThumb2',(-sign*.48,.76,-.44)),(side+'HandThumb3',(-sign*.96,-.25,.10))]:
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
    # The off hand rises into a compact guard while the right hand strikes.
    guard = closure * min(1.0,frame/7.0)
    left_wrist = Vector((.27,-.35,1.35)).lerp(Vector((.285,-.305,1.405)),guard)
    arms = {'Right':arm('Right',wrist,roll), 'Left':arm('Left',left_wrist,-70)}
    fingers('Right',closure); fingers('Left',closure)
    bpy.data.objects['Human_Body'].data.shape_keys.key_blocks['TP_Grip_Right_Closed'].value = 0
    bpy.context.view_layer.update()
    close_thumb('Right',closure); close_thumb('Left',closure)
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
for title, frame in [('NEUTRAL',0),('FIST CLOSED',7),('DRIVE',11),('CONTACT',CONTACT),('WITHDRAW',25),('RELAX',44)]: scene.timeline_markers.new(title,frame=frame)
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
report = {'status':'Reworked after user rejected v1; appearance review pending','source':str(source.relative_to(ROOT)),
          'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'fps':FPS,'duration':END/FPS,'contact_frame':CONTACT,
          'poses':POSES,'samples':samples}
(OUT/'Human.unarmed.json').write_text(json.dumps(report,indent=2))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.unarmed.blend'),compress=True)
print('UNARMED_AUTHORED',json.dumps({k:v for k,v in report.items() if k not in ['poses','samples']}))
