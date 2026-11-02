# SPDX-License-Identifier: 0BSD
import hashlib
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'reviews/player_wakeup'
OUTPUT.mkdir(parents=True, exist_ok=True)
(OUTPUT / '.gdignore').touch()
source = Path(bpy.data.filepath)
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
rig.animation_data.action = bpy.data.actions['Idle']
rig.animation_data.action_slot = rig.animation_data.action.slots[0]
scene.frame_set(1)
bpy.context.view_layer.update()
base = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type == 'MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)

def aim(name, head, direction):
    bone = rig.pose.bones[name]
    rest = rig.data.bones[name].matrix_local.to_quaternion()
    rotation = (rest @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ rest
    bone.matrix = Matrix.LocRotScale(head, rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()

def pose(right, left, curl, roll):
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.matrix_basis = base[bone.name]
    bpy.context.view_layer.update()
    for prefix, side, target in [('Right', -1, right), ('Left', 1, left)]:
        shoulder = rig.pose.bones[prefix + 'Arm'].head.copy()
        wrist = Vector(target)
        upper = rig.data.bones[prefix + 'Arm'].length
        lower = rig.data.bones[prefix + 'ForeArm'].length
        direction = wrist - shoulder
        distance = min(direction.length, upper + lower - .01)
        axis = direction.normalized()
        wrist = shoulder + axis * distance
        along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
        pole = Vector((side * .60, -.06, 1.36)) - shoulder
        pole = (pole - axis * pole.dot(axis)).normalized()
        elbow = shoulder + axis * along + pole * math.sqrt(max(0, upper * upper - along * along))
        aim(prefix + 'Arm', shoulder, elbow - shoulder)
        aim(prefix + 'ForeArm', elbow, wrist - elbow)
        direction = (wrist - elbow).normalized()
        forearm = rig.pose.bones[prefix + 'ForeArm']
        forearm_rotation = Quaternion(direction, math.radians(roll * side * 1.5)) @ forearm.matrix.to_quaternion()
        forearm.matrix = Matrix.LocRotScale(elbow, forearm_rotation, Vector((1, 1, 1)))
        bpy.context.view_layer.update()
        aim(prefix + 'Hand', wrist, direction)
        hand = rig.pose.bones[prefix + 'Hand']
        rotation = Quaternion(direction, math.radians(roll * side * 2.0)) @ hand.matrix.to_quaternion()
        hand.matrix = Matrix.LocRotScale(wrist, rotation, Vector((1, 1, 1)))
        for finger, amount in [('Index', .55), ('Middle', .75), ('Ring', .95), ('Pinky', 1.1), ('Thumb', .35)]:
            for joint in range(1, 4):
                rig.pose.bones[f'{prefix}Hand{finger}{joint}'].rotation_quaternion = Quaternion((1, 0, 0), -math.radians(curl * amount * (1 if joint == 2 else .65)))
        bpy.context.view_layer.update()
    return {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}

keys = [
    (0, (-.27, -.28, 1.12), (.26, -.25, 1.10), 22, 0),
    (20, (-.22, -.32, 1.64), (.29, -.28, 1.18), 24, -12),
    (35, (-.18, -.31, 1.65), (.28, -.30, 1.20), 29, -8),
    (48, (-.23, -.33, 1.60), (.27, -.33, 1.25), 20, -15),
    (64, (-.26, -.46, 1.43), (.25, -.43, 1.39), 10, 32),
    (78, (-.25, -.44, 1.44), (.24, -.46, 1.43), 32, 40),
    (92, (-.27, -.45, 1.40), (.26, -.43, 1.42), 14, 24),
    (108, (-.28, -.38, 1.29), (.27, -.34, 1.25), 22, 8),
    (132, (-.28, -.27, 1.06), (.27, -.25, 1.04), 23, 0),
]
poses = [(frame, pose(right, left, curl, roll)) for frame, right, left, curl, roll in keys]
action = bpy.data.actions.new('FP_Wake_Confused_Review')
rig.animation_data_create()
rig.animation_data.action = action
scene.render.fps = 30
scene.frame_start, scene.frame_end = 0, 132
for frame, values in poses:
    scene.frame_set(frame)
    for bone in rig.pose.bones:
        bone.location, bone.rotation_quaternion, bone.scale = values[bone.name].decompose()
        for channel in ['location', 'rotation_quaternion', 'scale']:
            bone.keyframe_insert(channel, frame=frame, group=bone.name)
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:
                    key.interpolation = 'BEZIER'
                    key.handle_left_type = key.handle_right_type = 'AUTO_CLAMPED'
action.use_fake_user = True
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
scene.frame_set(0)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT / 'Human.wakeup.glb'), export_format='GLB', use_selection=True, export_materials='NONE', export_animations=True, export_animation_mode='ACTIONS', export_frame_range=True, export_force_sampling=True, export_skins=True, export_morph=False, export_yup=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / 'Human.wakeup.blend'), compress=True)
(OUTPUT / 'provenance.json').write_text(json.dumps({'creator': 'TerraForest original AI-assisted motion authoring', 'license': 'CC0-1.0 for new motion; inherited Human R11 rig notices remain applicable', 'source': source.relative_to(ROOT).as_posix(), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'files': ['Human.wakeup.blend', 'Human.wakeup.glb', 'Human.wakeup.res'], 'purpose': 'First-person confused waking motion, 4.4 seconds plus 0.6 second equipment return', 'approval': 'Re-authored output requires comparison with the approved 2026-11-02 preview before replacing the runtime asset', 'tool': 'Blender ' + bpy.app.version_string, 'frames': [0, 132], 'fps': 30}, indent=2) + '\n')
print('WAKEUP_AUTHORED')
