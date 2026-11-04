# SPDX-License-Identifier: 0BSD
"""Review-only generic item hold/equip/use on the existing R11 rig.

Open Human.torch.blend for its repaired body and fitted arm reference. New
motion and palm cradle are original; arm transport follows author_torch_attack.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import time
import uuid
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'addons/characters/authoring'
source = Path(bpy.data.filepath)
assert source.name == 'Human.torch.blend'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
rig = bpy.data.objects['Human_Rig']
body = bpy.data.objects['Human_Body']
scene = bpy.context.scene
idle = bpy.data.actions['FP_Torch_Idle']
rig.animation_data.action = idle
if idle.slots:
    rig.animation_data.action_slot = idle.slots[0]
scene.frame_set(0)
bpy.context.view_layer.update()
base = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
reference = {b.name: b.matrix.copy() for b in rig.pose.bones}
for obj in list(bpy.data.objects):
    obj.animation_data_clear()
    if obj.type == 'MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            if key.name != 'Basis':
                key.value = 0
    if obj not in [rig, body]:
        bpy.data.objects.remove(obj, do_unlink=True)
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)


def aim(name, head, direction):
    q = reference[name].to_quaternion()
    q = (q @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ q
    rig.pose.bones[name].matrix = Matrix.LocRotScale(head, q, Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    return q


def right_arm(wrist):
    origin = rig.pose.bones['RightArm'].head.copy()
    delta = wrist - origin
    distance = delta.length
    a, b = [rig.data.bones['Right' + n].length for n in ['Arm', 'ForeArm']]
    assert abs(a-b)+.002 < distance < a+b-.004, (scene.frame_current, distance, a+b)
    axis = delta.normalized()
    along = (a*a-b*b+distance*distance)/(2*distance)
    pole = Vector((-.40, -.09, 1.15)) - origin
    pole = (pole-axis*pole.dot(axis)).normalized()
    elbow = origin + axis*along + pole*math.sqrt(max(0, a*a-along*along))
    aim('RightArm', origin, elbow-origin)
    forearm = aim('RightForeArm', elbow, wrist-elbow)
    # Supinate the forearm and hand together: palm faces upward, with the wrist
    # still aligned to the forearm. Preserve the upper arm's reference roll.
    y = (wrist-elbow).normalized()
    current = forearm @ Vector((0, 0, -1))
    desired = (Vector((0, 0, 1))-y*y.z).normalized()
    current = (current-y*current.dot(y)).normalized()
    angle = math.atan2(y.dot(current.cross(desired)), current.dot(desired))
    forearm = Quaternion(y, angle) @ forearm
    rig.pose.bones['RightForeArm'].matrix = Matrix.LocRotScale(elbow, forearm, Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    rig.pose.bones['RightHand'].matrix = Matrix.LocRotScale(wrist, forearm, Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    return {'wrist': list(wrist), 'elbow': list(elbow), 'shoulder': list(origin), 'reach': distance/(a+b)}


def cradle_fingers():
    hand = rig.pose.bones['RightHand'].matrix.copy()
    q = hand.to_quaternion()
    # Rebuild a soft open cradle, rather than retaining the cylindrical torch
    # grip. Phalanges keep their original offsets and lengths.
    for finger, angles in [('Index', (2, 5, 8)), ('Middle', (3, 6, 9)),
                           ('Ring', (5, 8, 12)), ('Pinky', (8, 10, 14))]:
        for joint, angle in enumerate(angles, 1):
            bone = rig.pose.bones[f'RightHand{finger}{joint}']
            direction = q @ Vector((0, math.cos(math.radians(angle)), -math.sin(math.radians(angle))))
            old = bone.matrix.to_quaternion()
            rotation = (old @ Vector((0, 1, 0))).rotation_difference(direction) @ old
            bone.matrix = Matrix.LocRotScale(bone.head, rotation, Vector((1, 1, 1)))
            bpy.context.view_layer.update()
    sign = 1 if (hand.inverted() @ rig.pose.bones['RightHandThumb1'].head).x > 0 else -1
    for joint, direction in enumerate([(sign*.65, .75, -.05), (sign*.1, .98, -.1), (-sign*.15, .97, -.15)], 1):
        bone = rig.pose.bones[f'RightHandThumb{joint}']
        old = bone.matrix.to_quaternion()
        desired = q @ Vector(direction).normalized()
        rotation = (old @ Vector((0, 1, 0))).rotation_difference(desired) @ old
        bone.matrix = Matrix.LocRotScale(bone.head, rotation, Vector((1, 1, 1)))
        bpy.context.view_layer.update()


def restore():
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.matrix_basis = Matrix.Identity(4) if bone.name.startswith('RightHand') and bone.name != 'RightHand' else base[bone.name]
    bpy.context.view_layer.update()


def ease(value):
    return value*value*(3-2*value)


def pose(motion, frame, count):
    restore()
    wrist = Vector((-.235, -.40, 1.43))
    t = frame/count
    if motion == 'Hold':
        wrist += Vector((.0015*math.sin(t*math.tau), 0, .0015*math.sin(t*math.tau)))
    elif motion == 'Equip':
        wrist = Vector((-.235, -.19, 1.08)).lerp(wrist, ease(t))
    else:
        # One continuous lift, short presentation, then return. This is an
        # item-agnostic gesture; no reading/eating game event is authored.
        lift = ease(t/.34) if t < .34 else (1 if t < .55 else 1-ease((t-.55)/.45))
        wrist = wrist.lerp(Vector((-.15, -.39, 1.52)), lift)
    record = right_arm(wrist)
    cradle_fingers()
    return record


actions = {}
records = {}
for motion, count in [('Hold', 120), ('Equip', 27), ('Use', 78)]:
    action = bpy.data.actions.new('FP_Item_' + motion)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    previous = {}
    samples = []
    for frame in range(count+1):
        scene.frame_set(frame)
        samples.append({'frame': frame, **pose(motion, frame, count)})
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
    action.frame_end = count
    actions[motion] = action
    records[motion] = {'frames': count, 'seconds': count/60, 'samples': samples}

# Measure actual weighted hand skin in the authored cradle for a shared support
# plane. Godot places each demonstration object's own bottom on that plane.
rig.animation_data.action = actions['Hold']
if actions['Hold'].slots:
    rig.animation_data.action_slot = actions['Hold'].slots[0]
scene.frame_set(0)
bpy.context.view_layer.update()
inverse = rig.pose.bones['RightHand'].matrix.inverted()
names = {group.index: group.name for group in body.vertex_groups}
palette = {b.name: b.matrix @ b.bone.matrix_local.inverted() for b in rig.pose.bones}
hand_points = []
for vertex in body.data.vertices:
    groups = [(names[g.group], g.weight) for g in vertex.groups if names[g.group] in palette]
    if sum(weight for name, weight in groups if name.startswith('RightHand')) < .8:
        continue
    point = sum(((palette[name] @ vertex.co)*weight for name, weight in groups), Vector((0, 0, 0)))
    point = inverse @ point
    if -.10 < point.x < .10 and -.01 < point.y < .24:
        hand_points.append(list(point))
support = float(np.array(hand_points)[:, 2].min()) - .0015
scene.render.fps = 60
scene.frame_start = 0
scene.frame_end = 120
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.item_use.glb'), export_format='GLB', use_selection=True,
                         export_materials='NONE', export_animations=True, export_animation_mode='ACTIONS',
                         export_frame_range=False, export_force_sampling=True, export_skins=True,
                         export_morph=False, export_yup=True)
bpy.context.preferences.filepaths.save_version = 0
# Save beside the destination under a unique name, then atomically replace it.
# Windows file watchers can briefly lock a just-written Blender destination.
temporary = OUT/('Human.item_use.tmp.'+uuid.uuid4().hex+'.blend')
bpy.ops.wm.save_as_mainfile(filepath=str(temporary), compress=True)
for attempt in range(20):
    try:
        os.replace(temporary, OUT/'Human.item_use.blend')
        break
    except PermissionError:
        if attempt == 19:
            raise
        time.sleep(.1)
metadata = {'status': 'Review-only candidate 01; player acceptance required before integration',
            'creator': 'TerraForest original AI-assisted motion authoring with OpenAI Codex',
            'license': 'CC0-1.0 new motion; inherited R11 rig/body/carry notices retained',
            'source': source.relative_to(ROOT).as_posix(), 'source_sha256': source_hash,
            'tool': 'Blender '+bpy.app.version_string, 'fps': 60,
            'prompt': 'Author a simple generic-item hold/use animation with a book, food or arbitrary object appearing in the hand; show it for approval before integration.',
            'actions': records, 'support_plane_hand_z': support, 'support_center_hand_y': .055,
            'support_vertices': len(hand_points), 'support_samples_hand': hand_points, 'external_motion': None,
            'demo_items': ['Existing CC0 field-manual mesh 214', 'Existing CC0 trail-bread mesh 218', 'Original neutral box proxy'],
            'scope': 'Pose-only, no item consumption, reading reward, damage, save/input or gameplay dispatch changes'}
(OUT/'Human.item_use.json').write_text(json.dumps(metadata, indent=2)+'\n')
print('ITEM_USE_AUTHORED support_plane=', support, 'vertices=', len(hand_points))
