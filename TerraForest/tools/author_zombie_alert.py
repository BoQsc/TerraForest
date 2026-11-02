# SPDX-License-Identifier: 0BSD
import hashlib
import json
import math
from pathlib import Path
import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'addons/characters/authoring'
source = Path(bpy.data.filepath)
rig = bpy.data.objects['Zombie_Rig']
scene = bpy.context.scene
action = bpy.data.actions['Zombie_Walk_Drag_Right']
rig.animation_data.action = action
rig.animation_data.action_slot = action.slots[0]
poses = []
for frame in range(121):
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    poses.append({bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones})
for obj in bpy.data.objects:
    obj.animation_data_clear()
for old in list(bpy.data.actions):
    bpy.data.actions.remove(old)

def aim(name, direction):
    bone = rig.pose.bones[name]
    matrix = bone.matrix.copy()
    rotation = matrix.to_3x3().col[1].normalized().rotation_difference(direction.normalized())
    result = (rotation.to_matrix() @ matrix.to_3x3()).to_4x4()
    result.translation = matrix.translation
    bone.matrix = result
    bpy.context.view_layer.update()

action = bpy.data.actions.new('Zombie_Alert_Walk')
rig.animation_data_create()
rig.animation_data.action = action
scene.render.fps = 60
scene.frame_start, scene.frame_end = 0, 120
for frame, values in enumerate(poses):
    scene.frame_set(frame)
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.matrix_basis = values[bone.name]
    for name, degrees in [('Spine', 3), ('Spine1', 4), ('Spine2', 3), ('Neck', -3), ('Head', -3)]:
        bone = rig.pose.bones[name]
        bone.rotation_quaternion = bone.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(degrees))
    bpy.context.view_layer.update()
    for prefix, side in [('Left', 1), ('Right', -1)]:
        swing = math.sin(math.tau * frame / 120 + side * .8)
        aim(prefix + 'Arm', Vector((side * .09, -.16 + swing * .025, -.24)))
        aim(prefix + 'ForeArm', Vector((side * -.02, -.24, -.06 + swing * .03)))
    for bone in rig.pose.bones:
        for channel in ['location', 'rotation_quaternion', 'scale']:
            bone.keyframe_insert(channel, frame=frame, group=bone.name)
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:
                    key.interpolation = 'LINEAR'
action.use_fake_user = True
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Z_Torso'].select_set(True)
bpy.context.view_layer.objects.active = rig
scene.frame_set(0)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT / 'Zombie.alert.glb'), export_format='GLB', use_selection=True, export_materials='NONE', export_animations=True, export_animation_mode='ACTIONS', export_frame_range=True, export_force_sampling=True, export_skins=True, export_morph=False, export_yup=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / 'Zombie.alert.blend'), compress=True)
(OUTPUT / 'Zombie.alert.json').write_text(json.dumps({'creator': 'TerraForest original AI-assisted motion authoring', 'license': 'CC0-1.0 new animation; preserved original zombie notices', 'source': source.relative_to(ROOT).as_posix(), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'tool': 'Blender ' + bpy.app.version_string, 'purpose': 'Upper-body alert hunch and reaching arms; original drag-walk hips and feet remain unchanged', 'files': ['Zombie.alert.blend', 'Zombie.alert.glb', '../runtime/assets/Zombie.alert.res']}, indent=2) + '\n')
print('ZOMBIE_ALERT_AUTHORED')
