# SPDX-License-Identifier: 0BSD
"""Separate diagonal carry and right-to-left stroke on the original R11 rig."""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'addons/characters/authoring'
REPORT = ROOT/'reports/pickaxe_crosscut'
source = Path(bpy.data.filepath)
assert source.name == 'Human.r11.blend', 'Start from original R11 rig, never a swing derivative'
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
FPS, END, CONTACT = 120, 192, 84
DURATIONS = {"Idle":2.0,"Swing":1.6,"Walk":1.0,"Run":.8,"Jump":1.5}
TIP = Vector((-.326, 0, .535))
GRIP_STATIONS = {'Left': -.22, 'Right': .11}
GRIP_ROLL = {'Left': 0, 'Right': 30}

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
for side, angle in GRIP_ROLL.items():
    # Re-seat the closed hand around the cylindrical shaft once, not during
    # the animation. This lets the raised right wrist lead from a lower elbow.
    around_shaft = Matrix.Rotation(math.radians(angle),4,'Z')
    grip_shapes[side] = around_shaft @ grip_shapes[side]
    forearm_roll[side] = around_shaft @ forearm_roll[side]
finger_shapes = {b.name: b.matrix_basis.copy() for b in rig.pose.bones
                 if any(part in b.name for part in ['HandIndex', 'HandMiddle', 'HandRing', 'HandPinky', 'HandThumb'])}

# Original lower-body gaits are independent of the newly authored upper body.
gaits={}
for motion in ['Walk','Run','Jump']:
    action=bpy.data.actions[motion];rig.animation_data.action=action
    if action.slots:rig.animation_data.action_slot=action.slots[0]
    start,end=action.frame_range;count=round(DURATIONS[motion]*FPS);gaits[motion]=[]
    for frame in range(count+1):
        at=start+(end-start)*frame/count;scene.frame_set(int(at),subframe=at-int(at));bpy.context.view_layer.update()
        gaits[motion].append({b.name:b.matrix_basis.copy() for b in rig.pose.bones})
    if motion!='Jump':gaits[motion][-1]=gaits[motion][0]

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

# Pose-table frame at 60 Hz (baked at 120 Hz), lower wrist XYZ, shaft forward pitch, right lean, blade-plane yaw,
# torso forward pitch, torso yaw, pelvis Z. Blender -X is player right; -Y forward.
# Raised ready pose: head near camera (+.56, +.31, -.69). At contact the
# working tip is on the camera centerline (0, 0, -.95), then follows down-left.
# Keep the original rig, camera and hand stations; solve the motion in the rig.
POSES = [
 (0, (-.03079903,-.26696229,1.51593435),16,50,15,3,-5,-.018),
 (10,(-.03432161,-.25425443,1.52649641),13,50,17,2,-7,-.016),
 (22,(-.01004905,-.20659295,1.53383720), 8,50,20,2,-12,-.014),
 (28,(-.01004905,-.18659291,1.53383720), 8,50,20,2,-12,-.014),
 (33,( .04197210,-.19180411,1.56805599),14,55,18,3,-8,-.020),
 (38,( .16642500,-.19859922,1.52081239),22,60,16,4,-1,-.025),
 (42,( .23358697,-.16472000,1.51675391),30,65,15,5, 4,-.030),
 (46,( .20316312,-.11304516,1.47717214),39,65,15,6, 7,-.035),
 (50,( .18150240,-.08339185,1.45278859),45,65,15,6, 8,-.035),
 (57,( .20877364,-.07557851,1.45076895),43,65,15,6, 8,-.035),
 (69,( .09534030,-.12909424,1.50202966),32,60,15,5, 2,-.025),
 (83,(-.03079903,-.26696229,1.51593435),16,50,15,3,-5,-.018),
 (96,(-.03079903,-.26696229,1.51593435),16,50,15,3,-5,-.018),
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
    assert abs(upper-lower)+.0002 < length < upper+lower-.0002, (scene.frame_current, end_name, length, upper+lower, list(target.translation), list(origin))
    axis = delta.normalized()
    along = (upper*upper-lower*lower+length*length)/(2*length)
    pole = pole_point-origin
    pole = (pole-axis*pole.dot(axis)).normalized()
    elbow = origin+axis*along+pole*math.sqrt(max(0,upper*upper-along*along))
    if end_name == 'LeftHand':
        # Match arm roll across the actual elbow bend. Using the rest arm or
        # the unaligned hand axis can cross a 180-degree singularity on a high
        # cross-body pose, spinning the upper arm or pinching the elbow skin.
        orient(lower_name,elbow,target.translation-elbow,lower_ref)
        forearm_pose = rig.pose.bones[lower_name].matrix.copy()
        orient(upper_name,origin,elbow-origin,forearm_pose)
        rig.pose.bones[lower_name].matrix = forearm_pose
        bpy.context.view_layer.update()
    else:
        orient(upper_name,origin,elbow-origin,upper_ref)
        orient(lower_name,elbow,target.translation-elbow,lower_ref)
    rig.pose.bones[end_name].matrix = target
    bpy.context.view_layer.update()
    return {'reach':length/(upper+lower),'endpoint_error_m':(rig.pose.bones[end_name].head-target.translation).length,'joint':list(elbow),'wrist_bend':math.degrees((target.translation-elbow).angle(target.to_quaternion()@Vector((0,1,0)))) if end_name.endswith('Hand') else 0}


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


def apply_pose(frame,motion="Swing",count=END):
    for bone in rig.pose.bones:bone.matrix_basis = finger_shapes.get(bone.name,Matrix.Identity(4))
    bpy.context.view_layer.update()
    data = channels(frame*.5 if motion=='Swing' else 0)
    anchor = Vector(data[:3]);pitch,lean,turn_yaw,torso,yaw,sink = data[3:]
    if motion in gaits:
        phase=frame/count*math.tau
        if motion=='Jump':anchor+=Vector((0,.010,-.020))*math.sin(phase*.5)**2
        else:
            strength=1 if motion=='Walk' else 1.6
            anchor+=Vector((.008*math.sin(phase),.005*math.sin(2*phase),.009*math.cos(2*phase)))*strength
            lean+=.8*math.sin(phase)*strength;pitch+=.8*math.sin(2*phase)*strength
    feet = body_pose(torso,yaw,sink)
    # Newly authored diagonal shaft and lateral strike plane.
    turn = Quaternion((0,0,1),math.radians(turn_yaw)) @ Quaternion((0,1,0),-math.radians(lean))
    angle = math.radians(pitch)
    shaft = turn @ Vector((0,-math.sin(angle),math.cos(angle)))
    blade = turn @ Vector((0, math.cos(angle),math.sin(angle)))
    side_axis = shaft.cross(blade)
    q = Matrix((blade,side_axis,shaft)).transposed().to_quaternion()
    grips = {side:grip_shapes[side].copy() for side in ['Left','Right']}
    for side in grips:grips[side].translation.z = GRIP_STATIONS[side]
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
        natural = Vector((sign*(.34+lift*.08),-.05,1.12+lift*.85))
        preferred = target.translation-(target.to_quaternion()@Vector((0,1,0)))*rig.data.bones[side+'ForeArm'].length
        pole = natural.lerp(preferred,.85)
        arms[side] = solve_pair(side+'Arm',side+'ForeArm',side+'Hand',target,pole,
                               rest_global[side+'Arm'],tool @ forearm_roll[side])
    if motion in gaits:
        for bone in rig.pose.bones:
            if any(part in bone.name for part in ['UpLeg','Leg','Foot','Toe']):bone.matrix_basis=gaits[motion][frame][bone.name]
        bpy.context.view_layer.update()
    return {'frame':frame,'working_tip':list(tool @ TIP),'head':list(tool @ Vector((0,0,.6))),
            'lower_wrist':list(anchor),'shaft_pitch':pitch,'shaft_lean':lean,'blade_yaw':turn_yaw,'grip_stations':GRIP_STATIONS,
            'torso_pitch':torso,'torso_yaw':yaw,'arms':arms,'feet':feet}


if '--probe' in sys.argv:
    for frame in [0,10,22,28,33,38,42,46,50,57,69,83,96]:
        scene.frame_set(frame*2)
        try:
            r=apply_pose(frame*2)
            print('PROBE',frame,'tip',r['working_tip'],'arms',{s:[round(r['arms'][s]['reach'],3),round(r['arms'][s]['wrist_bend'],1)] for s in ['Left','Right']})
        except AssertionError as error:print('PROBE_FAIL',error)

else:
    actions={};samples={}
    for suffix,duration in DURATIONS.items():
        end=round(duration*FPS);action=bpy.data.actions.new('FP_Pickaxe_Crosscut_'+suffix)
        rig.animation_data_create();rig.animation_data.action=action;action.use_fake_user=True
        samples[suffix]=[];previous={}
        for frame in range(end+1):
            scene.frame_set(frame);record=apply_pose(frame,suffix,end);samples[suffix].append(record)
            for bone in rig.pose.bones:
                if bone.name in previous and bone.rotation_quaternion.dot(previous[bone.name])<0:bone.rotation_quaternion.negate()
                previous[bone.name]=bone.rotation_quaternion.copy()
                for prop in ['location','rotation_quaternion','scale']:bone.keyframe_insert(prop,frame=frame,group=bone.name)
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:key.interpolation='LINEAR'
        action.use_frame_range=True;action.frame_start=0;action.frame_end=end;actions[suffix]=action
    scene.frame_start,scene.frame_end,scene.render.fps=0,END,FPS
    scene.timeline_markers.clear()
    for label,frame in [('DIAGONAL CARRY',0),('LOAD RIGHT',28),('DRIVE THROUGH',38),('CONTACT',42),('FOLLOW LEFT',50),('RECOVER',69),('READY',96)]:scene.timeline_markers.new(label,frame=frame*2)
    rig.animation_data.action=actions['Swing']
    if actions['Swing'].slots:rig.animation_data.action_slot=actions['Swing'].slots[0]
    scene.frame_set(0)
    rig['pickaxe_description']='SEPARATE UNAPPROVED CANDIDATE. Diagonal hold and newly authored right-to-left stroke, both hands fixed; ordinary accepted default unchanged.'
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
    bpy.data.objects['Human_Body'].select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.pickaxe_crosscut.glb'),export_format='GLB',use_selection=True,
        export_materials='NONE',export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,
        export_force_sampling=True,export_skins=True,export_morph=False,export_yup=True)
    report={'status':'Separate candidate; user approval required before default promotion',
            'grip_stations':GRIP_STATIONS,'fixed_grip_roll_degrees':GRIP_ROLL,'source':str(source.relative_to(ROOT)),
            'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'motion_source':'Raised upper-right hold and cursor-centered descending stroke, revised after user playtest. Original static finger wraps only. No accepted swing keys copied.',
            'fps':FPS,'durations':DURATIONS,'contact_frame':CONTACT,'poses':POSES,'samples':samples}
    (OUT/'Human.pickaxe_crosscut.json').write_text(json.dumps(report,indent=2))
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.pickaxe_crosscut.blend'),compress=True)
    print('PICKAXE_CROSSCUT_AUTHORED',json.dumps({k:v for k,v in report.items() if k not in ['samples','poses']}))
