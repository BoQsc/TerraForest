# SPDX-License-Identifier: 0BSD
"""Fresh pose blockout on neutral R11: no previous swing or motion keys read."""
import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'addons/characters/authoring'
REPORT = ROOT/'reports/pickaxe_fresh'
source = Path(bpy.data.filepath)
assert source.name == 'Human.r11.blend', 'Start from original R11 rig, never a swing derivative'
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
FPS, END, CONTACT = 60, 102, 50
TIP = Vector((-.326, 0, .535))

# Only static finger closure and hand-to-shaft orientation are reused. No body
# pose, ready transform, timing, path, or swing keys are copied from any action.
grip_action = bpy.data.actions['FP_Pickaxe_RightGrip_Idle']
rig.animation_data.action = grip_action
if grip_action.slots:
    rig.animation_data.action_slot = grip_action.slots[0]
scene.frame_set(1)
bpy.context.view_layer.update()
source_tool = rig.pose.bones['Weapon_Pickaxe'].matrix.copy()
grip_shapes = {side: source_tool.inverted() @ rig.pose.bones[side+'Hand'].matrix for side in ['Left', 'Right']}
forearm_roll = {side: source_tool.inverted() @ rig.pose.bones[side+'ForeArm'].matrix for side in ['Left', 'Right']}
finger_shapes = {b.name: b.matrix_basis.copy() for b in rig.pose.bones
                 if any(part in b.name for part in ['HandIndex', 'HandMiddle', 'HandRing', 'HandPinky', 'HandThumb'])}

for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type == 'MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            if key.name != 'Basis':key.value = 0
for action in list(bpy.data.actions):bpy.data.actions.remove(action)
for bone in rig.pose.bones:
    bone.rotation_mode = 'QUATERNION'
    bone.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
rest_global = {b.name: b.matrix.copy() for b in rig.pose.bones}
foot_targets = {}
for side, shift in [('Left', (.045, -.05, 0)), ('Right', (-.045, .055, 0))]:
    foot_targets[side] = rest_global[side+'Foot'].copy()
    foot_targets[side].translation += Vector(shift)

# Explicit new anatomical poses: frame, lower wrist XYZ, shaft pitch from up,
# lateral shaft lean, upper grip station, torso forward pitch, torso yaw, pelvis Z.
# The pick's negative X blade is aligned with the sagittal working plane.
POSES = [
 (0,   (-.035,-.28, 1.19),  28, 16, .11,   5, -2, -.022),
 (12,  (-.085,-.25, 1.29),   4, 20, .145,  4, -4, -.017),
 (24,  (-.165,-.20, 1.40), -29, 23, .18,   2, -7, -.010),
 (32,  (-.180,-.19, 1.43), -38, 24, .18,   1, -8, -.008),
 (37,  (-.155,-.22, 1.40), -25, 21, .15,   3, -5, -.015),
 (42,  (-.115,-.25, 1.32),   0, 16, .065,  6, -1, -.025),
 (47,  (-.080,-.27, 1.21),  28, 12,-.025,  9,  3, -.035),
 (50,  (-.065,-.27, 1.16),  40, 11,-.065, 10,  4, -.038),
 (53,  (-.065,-.25, 1.15),  42, 11,-.065, 11,  4, -.040),
 (60,  (-.060,-.22, 1.14),  37, 13,-.065, 10,  3, -.035),
 (72,  (-.050,-.25, 1.19),  27, 16,-.015,  7,  0, -.028),
 (88,  (-.035,-.28, 1.19),  25, 16, .09,   5, -2, -.023),
 (102, (-.035,-.28, 1.19),  28, 16, .11,   5, -2, -.022),
]


def channels(frame):
    values = [[*row[1], *row[2:]] for row in POSES]
    def tangent(i, c):
        if i in (0, len(POSES)-1):return 0.0
        a = (values[i][c]-values[i-1][c])/(POSES[i][0]-POSES[i-1][0])
        b = (values[i+1][c]-values[i][c])/(POSES[i+1][0]-POSES[i][0])
        return 2*a*b/(a+b) if a*b > 0 else 0.0
    for i, (a, b) in enumerate(zip(POSES, POSES[1:])):
        if a[0] <= frame <= b[0]:
            dt = b[0]-a[0];t = (frame-a[0])/dt
            return [(2*t**3-3*t*t+1)*values[i][c]+(t**3-2*t*t+t)*dt*tangent(i,c)
                    +(-2*t**3+3*t*t)*values[i+1][c]+(t**3-t*t)*dt*tangent(i+1,c) for c in range(len(values[0]))]
    raise ValueError(frame)


def orient(name, head, direction, reference):
    old = reference.to_quaternion()
    q = (old @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ old
    rig.pose.bones[name].matrix = Matrix.LocRotScale(head, q, Vector((1,1,1)))
    bpy.context.view_layer.update()


def solve_pair(upper_name, lower_name, end_name, target, pole_point, upper_ref, lower_ref):
    origin = rig.pose.bones[upper_name].head.copy()
    delta = target.translation-origin
    length = delta.length
    upper, lower = rig.data.bones[upper_name].length, rig.data.bones[lower_name].length
    assert abs(upper-lower)+.0002 < length < upper+lower-.0002, (scene.frame_current, end_name, length, upper+lower)
    axis = delta.normalized()
    along = (upper*upper-lower*lower+length*length)/(2*length)
    pole = pole_point-origin
    pole = (pole-axis*pole.dot(axis)).normalized()
    elbow = origin+axis*along+pole*math.sqrt(max(0,upper*upper-along*along))
    orient(upper_name,origin,elbow-origin,upper_ref)
    orient(lower_name,elbow,target.translation-elbow,lower_ref)
    rig.pose.bones[end_name].matrix = target
    bpy.context.view_layer.update()
    return {'reach':length/(upper+lower),'endpoint_error_m':(rig.pose.bones[end_name].head-target.translation).length,'joint':list(elbow)}


def body_pose(pitch, yaw, sink):
    hips = rig.pose.bones['Hips']
    pelvis = hips.matrix.copy()
    pelvis.translation += Vector((-.006*yaw/8, -.012*pitch/10, sink-.025))
    hips.matrix = pelvis
    bpy.context.view_layer.update()
    for name in ['Spine','Spine1','Spine2']:
        bone = rig.pose.bones[name];at = bone.matrix.copy()
        q = Quaternion((0,0,1),math.radians(yaw/3)) @ Quaternion((1,0,0),math.radians(pitch/3))
        bone.matrix = Matrix.LocRotScale(at.translation,q @ at.to_quaternion(),Vector((1,1,1)))
        bpy.context.view_layer.update()
    # Maintain gaze while the shoulders and torso move under the stable camera.
    neck = rig.pose.bones['Neck'];at = neck.matrix.copy()
    q = Quaternion((0,0,1),math.radians(-yaw)) @ Quaternion((1,0,0),math.radians(-pitch*.75))
    neck.matrix = Matrix.LocRotScale(at.translation,q @ at.to_quaternion(),Vector((1,1,1)))
    bpy.context.view_layer.update()
    feet = {}
    for side in ['Left','Right']:
        sign = 1 if side=='Left' else -1
        feet[side] = solve_pair(side+'UpLeg',side+'Leg',side+'Foot',foot_targets[side],
            Vector((sign*.20,-.40,.48)),rest_global[side+'UpLeg'],rest_global[side+'Leg'])
    return feet


def apply_pose(frame):
    for bone in rig.pose.bones:bone.matrix_basis = finger_shapes.get(bone.name,Matrix.Identity(4))
    bpy.context.view_layer.update()
    data = channels(frame)
    anchor = Vector(data[:3]);pitch,lean,station,torso,yaw,sink = data[3:]
    feet = body_pose(torso,yaw,sink)
    # An explicit tool basis gives a new upright hold and shoulder-height chop.
    turn = Quaternion((0,0,1),math.radians(15)) @ Quaternion((0,1,0),-math.radians(lean))
    angle = math.radians(pitch)
    shaft = turn @ Vector((0,-math.sin(angle),math.cos(angle)))
    blade = turn @ Vector((0, math.cos(angle),math.sin(angle)))
    side_axis = shaft.cross(blade)
    q = Matrix((blade,side_axis,shaft)).transposed().to_quaternion()
    grips = {side:grip_shapes[side].copy() for side in ['Left','Right']}
    grips['Left'].translation.z = -.22
    grips['Right'].translation.z = station
    tool = Matrix.LocRotScale(anchor-q @ grips['Left'].translation,q,Vector((1,1,1)))
    rig.pose.bones['Weapon_Pickaxe'].matrix = tool
    bpy.context.view_layer.update()
    arms = {}
    for side in ['Left','Right']:
        sign = 1 if side=='Left' else -1
        target = tool @ grips[side]
        shoulder = rig.pose.bones[side+'Shoulder']
        # Clavicle elevation follows the raised upper hand, then settles.
        lift = max(0,target.translation.z-1.43)
        direction = Vector((sign*.14,-.035,.005+lift*.20))
        orient(side+'Shoulder',shoulder.head.copy(),direction,rest_global[side+'Shoulder'])
        pole = Vector((sign*(.34+lift*.08),-.05,1.12+lift*.85))
        arms[side] = solve_pair(side+'Arm',side+'ForeArm',side+'Hand',target,pole,
                               rest_global[side+'Arm'],tool @ forearm_roll[side])
    return {'frame':frame,'working_tip':list(tool @ TIP),'head':list(tool @ Vector((0,0,.6))),
            'lower_wrist':list(anchor),'shaft_pitch':pitch,'upper_grip_station':station,
            'torso_pitch':torso,'torso_yaw':yaw,'arms':arms,'feet':feet}


actions = {};samples = []
for suffix, end in [('Idle',120),('Swing',END)]:
    action = bpy.data.actions.new('FP_Pickaxe_Fresh_'+suffix)
    rig.animation_data_create();rig.animation_data.action = action
    action.use_fake_user = True
    for frame in (range(end+1) if suffix=='Swing' else [0,end]):
        scene.frame_set(frame)
        record = apply_pose(frame if suffix=='Swing' else 0)
        for bone in rig.pose.bones:
            bone.keyframe_insert('location',frame=frame,group=bone.name)
            bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
            bone.keyframe_insert('scale',frame=frame,group=bone.name)
        if suffix=='Swing':samples.append(record)
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    action.use_frame_range = True;action.frame_start = 0;action.frame_end = end
    actions[suffix] = action

scene.frame_start,scene.frame_end,scene.render.fps = 0,END,FPS
scene.timeline_markers.clear()
for label,frame in [('NEW LOW HOLD',0),('LIFT / OPEN GRIP',24),('SHOULDER LOAD',32),
                    ('DROP / SLIDE UPPER HAND',42),('CONTACT',50),('SETTLE',53),('RECOVER GRIP',72),('READY',102)]:
    scene.timeline_markers.new(label,frame=frame)
rig.animation_data.action = actions['Swing']
if actions['Swing'].slots:rig.animation_data.action_slot=actions['Swing'].slots[0]
scene.frame_set(0)
rig['pickaxe_description']='FRESH ROUGH BLOCKOUT. Neutral body/rest rig, newly authored poses and 1.7s timing, sliding right grip. No old swing keys or rejected animation. User visual review required before polish or default selection.'
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.pickaxe_fresh.glb'),export_format='GLB',use_selection=True,
    export_materials='NONE',export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,
    export_force_sampling=True,export_skins=True,export_morph=False,export_yup=True)
report={'status':'ROUGH BLOCKOUT; pending user visual review; not default; no commit',
        'source':str(source.relative_to(ROOT)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'motion_source':'New authored pose table on reset rest rig. Only static hand closure/orientation fitted to original shaft is reused.',
        'reference':'https://www.waterways.org.uk/wp-content/uploads/2021/04/Hand-Tools-Use-Care-_-Maintenance.pdf#page=7',
        'fps':FPS,'duration':END/FPS,'contact_frame':CONTACT,'poses':POSES,'samples':samples}
(OUT/'Human.pickaxe_fresh.json').write_text(json.dumps(report,indent=2))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.pickaxe_fresh.blend'),compress=True)
print('PICKAXE_FRESH_AUTHORED',json.dumps({k:v for k,v in report.items() if k not in ['samples','poses']}))
