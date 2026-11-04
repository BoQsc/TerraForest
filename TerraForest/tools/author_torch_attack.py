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
grip = rig.pose.bones['Weapon_Axe'].matrix.inverted() @ rig.pose.bones['RightHand'].matrix
left = rig.pose.bones['LeftHand'].matrix.copy()
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
rest = {b.name: b.matrix.copy() for b in rig.pose.bones}
previous_pole = None


def orient(name, head, direction, reference):
    q = reference.to_quaternion()
    q = (q @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ q
    rig.pose.bones[name].matrix = Matrix.LocRotScale(head, q, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def arm(side, target):
    global previous_pole
    sign = 1 if side == 'Left' else -1
    shoulder = rig.pose.bones[side + 'Shoulder']
    orient(side + 'Shoulder', shoulder.head.copy(), Vector((sign * .14, -.05, -.005)), rest[side + 'Shoulder'])
    origin = rig.pose.bones[side + 'Arm'].head.copy()
    delta = target.translation - origin
    distance = delta.length
    a, b = [rig.data.bones[side + part].length for part in ['Arm', 'ForeArm']]
    assert abs(a - b) + .001 < distance < a + b - .001, (scene.frame_current, distance, a + b)
    axis = delta.normalized()
    along = (a * a - b * b + distance * distance) / (2 * distance)
    preferred = target.translation - (target.to_quaternion() @ Vector((0, 1, 0))) * b
    pole = Vector((sign * .42, -.05, 1.23)).lerp(preferred, .90) - origin
    pole = (pole - axis * pole.dot(axis)).normalized()
    # Near a straight wrist, its preferred elbow plane can turn rapidly.
    # Transport the preceding bend plane and bound its orbit; bone lengths,
    # hand target and fitted grip remain exact at every authored key.
    if previous_pole is not None:
        carried = (previous_pole - axis * previous_pole.dot(axis)).normalized()
        turn = carried.angle(pole)
        if turn > .20:
            pole = carried.slerp(pole, .20 / turn).normalized()
    previous_pole = pole.copy()
    elbow = origin + axis * along + pole * math.sqrt(max(0, a * a - along * along))
    width = target.to_quaternion() @ Vector((1, 0, 0))
    hinge = (elbow - origin).cross(target.translation - elbow).normalized()
    if side == 'Left':
        hinge = -hinge
    for name, head, direction in [(side + 'Arm', origin, elbow - origin), (side + 'ForeArm', elbow, target.translation - elbow)]:
        axis = direction.normalized()
        across = (width - axis * width.dot(axis)).normalized()
        if name == side + 'Arm':
            across = hinge
        q = Matrix((across, axis, across.cross(axis))).transposed().to_quaternion()
        rig.pose.bones[name].matrix = Matrix.LocRotScale(head, q, Vector((1, 1, 1)))
        bpy.context.view_layer.update()
    rig.pose.bones[side + 'Hand'].matrix = target
    bpy.context.view_layer.update()
    return {'reach_fraction': distance / (a + b),
            'wrist_bend': math.degrees((target.translation - elbow).angle(target.to_quaternion() @ Vector((0, 1, 0))))}


# Armature space: -X is player right, -Y is forward, +Z is up.
# Frame 26 is a proposed visual contact pose, not a gameplay damage event.
keys = [
    (0, (-.29, -.43, 1.37), 9, -7),
    (8, (-.31, -.39, 1.39), -2, -9),
    (15, (-.32, -.37, 1.42), -12, -10),
    (26, (-.15, -.49, 1.40), 22, 20),
    (32, (-.10, -.46, 1.36), 35, 25),
    (42, (-.21, -.42, 1.36), 15, 5),
    (66, (-.29, -.43, 1.37), 9, -7),
]
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
    start, end = next((a, b) for a, b in zip(keys, keys[1:]) if a[0] <= frame <= b[0])
    t = (frame - start[0]) / (end[0] - start[0])
    t = t * t * (3 - 2 * t)
    at = Vector(start[1]).lerp(Vector(end[1]), t)
    pitch, roll = [math.radians(start[i] + (end[i] - start[i]) * t) for i in [2, 3]]
    q = Quaternion((0, 1, 0), roll) @ Quaternion((1, 0, 0), pitch)
    tool = Matrix.LocRotScale(at, q, Vector((1, 1, 1)))
    rig.pose.bones['Weapon_Axe'].matrix = tool
    bpy.context.view_layer.update()
    right = arm('Right', tool @ grip)
    # The free hand stays in its existing relaxed carry pose.
    samples.append({'frame': frame, 'Right': right, 'tool_origin': list(at),
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
            'creator': 'TerraForest original AI-assisted motion authoring with OpenAI Codex',
            'license': 'CC0-1.0 for new motion; inherited R11 rig/mesh and existing torch notices retained',
            'source': source.relative_to(ROOT).as_posix(), 'source_sha256': source_hash,
            'tool': 'Blender ' + bpy.app.version_string,
            'prompt': 'Author a simple torch attack animation and show it for acceptance.',
            'external_motion': None, 'clip': action.name, 'fps': 60, 'frames': [0, 66],
            'seconds': 1.1, 'proposed_contact_frame': 26,
            'files': ['Human.torch_attack.blend', 'Human.torch_attack.glb', 'Human.torch_attack.json', 'Human.torch_attack.res'],
            'keys': keys, 'samples': samples}
(OUT / 'Human.torch_attack.json').write_text(json.dumps(metadata, indent=2) + '\n')
print('TORCH_ATTACK_AUTHORED', max(s['Right']['wrist_bend'] for s in samples), 'degrees maximum wrist bend')
