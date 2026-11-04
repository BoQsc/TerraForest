# SPDX-License-Identifier: 0BSD
"""Blender: author a review-only torch strike on the existing fitted R11 grip.

Open authoring/Human.torch.blend. No downloaded motion or new rig is used.
Arm solving follows the repository's author_wooden_torch.py (0BSD).
"""
import hashlib
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'addons/characters/authoring'
source = Path(bpy.data.filepath)
assert source.name == 'Human.torch.blend'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
idle = bpy.data.actions['FP_Torch_Idle']
rig.animation_data.action = idle
if idle.slots:
    rig.animation_data.action_slot = idle.slots[0]
scene.frame_set(0)
bpy.context.view_layer.update()
ready = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
ready_global = {b.name: b.matrix.copy() for b in rig.pose.bones}
grip = rig.pose.bones['Weapon_Axe'].matrix.inverted() @ rig.pose.bones['RightHand'].matrix
for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type == 'MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            if key.name != 'Basis':
                key.value = 0
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)
for bone in rig.pose.bones:
    bone.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
def aim_from_ready(name, head, direction, body_delta):
    # Preserve the fitted carry's bone roll. The rejected solver replaced the
    # upper-arm X axis with its elbow hinge and twisted the sleeve at impact.
    q = (body_delta @ ready_global[name]).to_quaternion()
    q = (q @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ q
    rig.pose.bones[name].matrix = Matrix.LocRotScale(head, q, Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    return q


def arm(target, body_delta, flex, pole_drop):
    origin = rig.pose.bones['RightArm'].head.copy()
    delta = target - origin
    distance = delta.length
    a, b = [rig.data.bones['Right' + part].length for part in ['Arm', 'ForeArm']]
    assert abs(a - b) + .001 < distance < a + b - .001, (scene.frame_current, distance, a + b)
    axis = delta.normalized()
    along = (a * a - b * b + distance * distance) / (2 * distance)
    # A low, outward elbow target is independent of the torch orientation.
    # Orient the wrist from the resulting forearm, instead of lifting the elbow
    # to satisfy an independently specified rigid tool angle.
    preferred = ready_global['RightForeArm'].translation + Vector((-.015 * pole_drop, -.015 * pole_drop, -.06 * pole_drop))
    pole = body_delta @ preferred - origin
    pole = (pole - axis * pole.dot(axis)).normalized()
    elbow = origin + axis * along + pole * math.sqrt(max(0, a * a - along * along))
    aim_from_ready('RightArm', origin, elbow - origin, body_delta)
    forearm_q = aim_from_ready('RightForeArm', elbow, target - elbow, body_delta)
    hand_relative = ready_global['RightForeArm'].to_quaternion().inverted() @ ready_global['RightHand'].to_quaternion()
    hand_q = forearm_q @ hand_relative @ Quaternion((0, 0, 1), -math.radians(flex))
    hand = Matrix.LocRotScale(target, hand_q, Vector((1, 1, 1)))
    rig.pose.bones['RightHand'].matrix = hand
    bpy.context.view_layer.update()
    tool = hand @ grip.inverted()
    rig.pose.bones['Weapon_Axe'].matrix = tool
    bpy.context.view_layer.update()
    return {'reach_fraction': distance / (a + b),
            'wrist_bend': math.degrees((target - elbow).angle(hand_q @ Vector((0, 1, 0)))),
            'elbow': list(elbow), 'shoulder': list(origin)}, tool


# Armature space: -X is player right, -Y is forward, +Z is up.
# Offsets from the fitted carry wrist, flex, torso yaw/pitch and elbow drop.
# Continuous Hermite tangents carry velocity through the contact pose.
# Frame 26 is a proposed visual contact pose, not a gameplay damage event.
keys = [
    (0, (0, 0, 0), 0, 0, 0, 0),
    (12, (.045, .015, .008), -5, -3, -.5, .1),
    (18, (.095, .005, .02), -8, -5, -1, .15),
    (26, (.14, -.075, -.065), 18, 4, 1.5, .8),
    (33, (.18, -.045, -.105), 24, 6, 2, 1),
    (46, (.07, -.005, -.02), 8, 2, .5, .4),
    (66, (0, 0, 0), 0, 0, 0, 0),
]


def trajectory(frame):
    values = [(*row[1], *row[2:]) for row in keys]
    i = next(i for i in range(len(keys) - 1) if keys[i][0] <= frame <= keys[i + 1][0])
    a, b = keys[i][0], keys[i + 1][0]
    def tangent(j):
        if j in [0, len(keys) - 1]:
            return [0] * len(values[j])
        return [(b-a) / (keys[j + 1][0] - keys[j - 1][0]) for a,b in zip(values[j-1],values[j+1])]
    t = (frame - a) / (b - a)
    before, after = tangent(i), tangent(i+1)
    return [(2*t**3 - 3*t*t + 1)*x + (t**3 - 2*t*t + t)*(b-a)*dx
            + (-2*t**3 + 3*t*t)*y + (t**3 - t*t)*(b-a)*dy
            for x,y,dx,dy in zip(values[i],values[i+1],before,after)]
action = bpy.data.actions.new('FP_Torch_Swing')
action.use_fake_user = True
rig.animation_data_create()
rig.animation_data.action = action
previous = {}
samples = []
for frame in range(67):
    scene.frame_set(frame)
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.matrix_basis = ready[bone.name]
    bpy.context.view_layer.update()
    value = trajectory(frame)
    at = Vector(value[:3]);flex, yaw, pitch, drop = value[3:]
    for name, weight in [('Spine1', .4), ('Spine2', .6)]:
        bone = rig.pose.bones[name];matrix = bone.matrix.copy()
        turn = Quaternion((0, 0, 1), math.radians(yaw*weight)) @ Quaternion((1, 0, 0), math.radians(pitch*weight))
        bone.matrix = Matrix.LocRotScale(matrix.translation, turn @ matrix.to_quaternion(), Vector((1, 1, 1)))
        bpy.context.view_layer.update()
    body_delta = rig.pose.bones['RightShoulder'].matrix @ ready_global['RightShoulder'].inverted()
    # A small free-arm counter movement follows the torso and returns to carry.
    rig.pose.bones['LeftArm'].rotation_quaternion = ready['LeftArm'].to_quaternion() @ Quaternion((1, 0, 0), math.radians(-yaw*.45))
    bpy.context.view_layer.update()
    target = body_delta @ (ready_global['RightHand'].translation + at)
    right, tool = arm(target, body_delta, flex, drop)
    samples.append({'frame': frame, 'Right': right, 'tool_origin': list(tool.translation),
                    'crown': list(tool @ Vector((0, 0, .47)))})
    for bone in rig.pose.bones:
        if bone.name in previous and bone.rotation_quaternion.dot(previous[bone.name]) < 0:
            bone.rotation_quaternion.negate()
        previous[bone.name] = bone.rotation_quaternion.copy()
        for prop in ['location', 'rotation_quaternion', 'scale']:
            bone.keyframe_insert(prop, frame=frame, group=bone.name)
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:
                    key.interpolation = 'LINEAR'
action.use_frame_range = True
action.frame_start = 0
action.frame_end = 66
scene.render.fps = 60
scene.frame_start = 0
scene.frame_end = 66
scene.frame_set(26)
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT / 'Human.torch_attack.glb'), export_format='GLB',
                         use_selection=True, export_materials='NONE', export_animations=True,
                         export_animation_mode='ACTIONS', export_frame_range=False,
                         export_force_sampling=True, export_skins=True, export_morph=False, export_yup=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'Human.torch_attack.blend'), compress=True)
metadata = {'status': 'Candidate; player visual review required before gameplay integration',
            'revision': 2,
            'creator': 'TerraForest original AI-assisted motion authoring with OpenAI Codex',
            'license': 'CC0-1.0 for new motion; inherited R11 rig/mesh and existing torch notices retained',
            'source': source.relative_to(ROOT).as_posix(), 'source_sha256': source_hash,
            'tool': 'Blender ' + bpy.app.version_string,
            'prompt': 'Fix rejected torch attack: shoulder/elbow deformation, first-person bulge, weak strike, frozen body and stop-start timing. Show revision for acceptance.',
            'external_motion': None, 'clip': action.name, 'fps': 60, 'frames': [0, 66],
            'seconds': 1.1, 'proposed_contact_frame': 26,
            'files': ['Human.torch_attack.blend', 'Human.torch_attack.glb', 'Human.torch_attack.json', 'Human.torch_attack.res'],
            'keys': keys, 'samples': samples}
(OUT / 'Human.torch_attack.json').write_text(json.dumps(metadata, indent=2) + '\n')
print('TORCH_ATTACK_AUTHORED', max(s['Right']['wrist_bend'] for s in samples), 'degrees maximum wrist bend')
