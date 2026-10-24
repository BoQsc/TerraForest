# SPDX-License-Identifier: 0BSD
"""Add restrained movement to the accepted hold, keeping both grips rigid."""
import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'addons/characters/authoring'
source = Path(bpy.data.filepath)
assert source.name == 'Human.pickaxe_fresh.blend'
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
FPS = 60
DURATIONS = {'Walk': 1.0, 'Run': .8, 'Jump': 1.5}


def sample(action, frame):
    rig.animation_data_create()
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(int(frame), subframe=frame-int(frame))
    bpy.context.view_layer.update()
    return {b.name: b.matrix_basis.copy() for b in rig.pose.bones}


base = sample(bpy.data.actions['FP_Pickaxe_Fresh_Idle'], 0)
globals_at_rest = {b.name: b.matrix.copy() for b in rig.pose.bones}
tool_at_rest = globals_at_rest['Weapon_Pickaxe']
grips = {side: tool_at_rest.inverted() @ globals_at_rest[side+'Hand'] for side in ['Left', 'Right']}
original = ROOT / 'addons/characters/Human_R11_Complete_Repost/Human.r11.blend'
with bpy.data.libraries.load(str(original), link=False) as (available, loaded):
    loaded.actions = ['Idle', *DURATIONS]
source_idle = sample(bpy.data.actions['Idle'], 1)
gaits = {}
for motion, duration in DURATIONS.items():
    action = bpy.data.actions[motion]
    start, end = action.frame_range
    count = round(duration*FPS)
    gaits[motion] = [sample(action, start+(end-start)*i/count) for i in range(count+1)]
    if motion != 'Jump':
        gaits[motion][-1] = gaits[motion][0]

for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type == 'MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            if key.name != 'Basis':
                key.value = 0
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)


def orient(name, head, direction, reference):
    old = reference.to_quaternion()
    rotation = (old @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ old
    rig.pose.bones[name].matrix = Matrix.LocRotScale(head, rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def fixed_arm(side, tool, delta):
    target = tool @ grips[side]
    upper, lower = rig.pose.bones[side+'Arm'], rig.pose.bones[side+'ForeArm']
    origin = upper.head.copy()
    vector = target.translation-origin
    length = vector.length
    a, b = upper.bone.length, lower.bone.length
    assert abs(a-b)+.0002 < length < a+b-.0002, (scene.frame_current, side, length)
    axis = vector.normalized()
    along = (a*a-b*b+length*length)/(2*length)
    # Use the accepted elbow plane, shifted gently with the carried tool.
    pole = globals_at_rest[side+'ForeArm'].translation + (tool.translation-tool_at_rest.translation)*.5-origin
    pole = (pole-axis*pole.dot(axis)).normalized()
    elbow = origin+axis*along+pole*math.sqrt(max(0, a*a-along*along))
    orient(side+'Arm', origin, elbow-origin, delta @ globals_at_rest[side+'Arm'])
    orient(side+'ForeArm', elbow, target.translation-elbow, delta @ globals_at_rest[side+'ForeArm'])
    rig.pose.bones[side+'Hand'].matrix = target
    bpy.context.view_layer.update()


records = {}
actions = {}
for motion, duration in DURATIONS.items():
    action = bpy.data.actions.new('FP_Pickaxe_Fresh_'+motion)
    rig.animation_data_create()
    rig.animation_data.action = action
    action.use_fake_user = True
    count = round(duration*FPS)
    records[motion] = []
    for frame in range(count+1):
        scene.frame_set(frame)
        gait = gaits[motion][frame]
        weight = 1.0
        if motion == 'Jump':
            edge = min(1.0, frame/10, (count-frame)/10)
            weight = edge*edge*(3-2*edge)
        for bone in rig.pose.bones:
            bone.rotation_mode = 'QUATERNION'
            bone.matrix_basis = base[bone.name]
            if any(part in bone.name for part in ['UpLeg', 'Leg', 'Foot', 'Toe']):
                bone.matrix_basis = base[bone.name].lerp(gait[bone.name], weight)
        # Keep the existing lower-body gait in place; never move the motor/root.
        # A carried tool stabilizes torso yaw. Keep the accepted upper-body
        # orientation and only a small vertical weight shift from the gait;
        # otherwise crossfading independent chains separates hand and shaft.
        hip_gait = base['Hips'].copy()
        hip_gait.translation.z += max(-.005,min(.005,(gait['Hips'].translation.z-source_idle['Hips'].translation.z)*.1*weight))
        rig.pose.bones['Hips'].matrix_basis = hip_gait
        phase = frame/count*math.tau
        if motion == 'Jump':
            lift = math.sin(phase*.5)**2
            offset = Vector((0, .012*lift, -.022*lift))
            angles = (2.0*lift, 0, 0)
            # Match the approved hold exactly at both airborne endpoints.
            if frame in [0, count]:
                for bone in rig.pose.bones:
                    bone.matrix_basis = base[bone.name]
        else:
            strength = 1.0 if motion == 'Walk' else 1.6
            offset = Vector((.012*math.sin(phase), .006*math.sin(2*phase), .014*math.cos(2*phase)))*strength
            angles = (1.1*math.sin(2*phase), .8*math.sin(phase), .6*math.sin(phase))
            angles = tuple(value*strength for value in angles)
        bpy.context.view_layer.update()
        rotation = (Quaternion((0,0,1), math.radians(angles[2]))
                    @ Quaternion((0,1,0), math.radians(angles[1]))
                    @ Quaternion((1,0,0), math.radians(angles[0])))
        # Rotate around the hands, not around the distant tool head or root.
        pivot = (globals_at_rest['LeftHand'].translation+globals_at_rest['RightHand'].translation)*.5
        delta = Matrix.Translation(pivot+offset) @ rotation.to_matrix().to_4x4() @ Matrix.Translation(-pivot)
        tool = delta @ tool_at_rest
        rig.pose.bones['Weapon_Pickaxe'].matrix = tool
        bpy.context.view_layer.update()
        for side in ['Left', 'Right']:
            fixed_arm(side, tool, delta)
        for bone in rig.pose.bones:
            bone.keyframe_insert('location', frame=frame, group=bone.name)
            bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
            bone.keyframe_insert('scale', frame=frame, group=bone.name)
        records[motion].append({'frame':frame, 'tool_origin':list(tool.translation)})
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'
    action.use_frame_range = True
    action.frame_start, action.frame_end = 0, count
    actions[motion] = action

scene.render.fps = FPS
scene.frame_start, scene.frame_end = 0, 60
scene.timeline_markers.clear()
rig.animation_data.action = actions['Walk']
if actions['Walk'].slots:
    rig.animation_data.action_slot = actions['Walk'].slots[0]
scene.frame_set(0)
rig['pickaxe_description'] = 'Fixed-grip locomotion follow-up. Accepted idle/swing remain separate and unchanged. Movement appearance awaiting playtest.'
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.pickaxe_locomotion.glb'), export_format='GLB', use_selection=True,
    export_materials='NONE', export_animations=True, export_animation_mode='ACTIONS', export_frame_range=False,
    export_force_sampling=True, export_skins=True, export_morph=False, export_yup=True)
report = {'source':str(source.relative_to(ROOT)), 'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
          'status':'Movement appearance awaiting playtest', 'fps':FPS, 'durations':DURATIONS,
          'method':'Accepted static tool/hand transforms; fixed-length arm solves; original in-place lower-body gaits.', 'samples':records}
(OUT/'Human.pickaxe_locomotion.json').write_text(json.dumps(report, indent=2))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.pickaxe_locomotion.blend'), compress=True)
print('PICKAXE_LOCOMOTION_AUTHORED', json.dumps(DURATIONS))
