# SPDX-License-Identifier: 0BSD
"""Revision 02: articulated generic item hold/equip/use on the existing R11 rig.

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


def articulated_arm(side, wrist, roll=0, flex=0, blend=1):
    origin = rig.pose.bones[side+'Arm'].head.copy()
    delta = wrist - origin
    distance = delta.length
    a, b = [rig.data.bones[side+n].length for n in ['Arm', 'ForeArm']]
    assert abs(a-b)+.002 < distance < a+b-.004, (scene.frame_current, distance, a+b)
    axis = delta.normalized()
    along = (a*a-b*b+distance*distance)/(2*distance)
    preferred = Vector((-.40 if side=='Right' else .39, -.09, 1.15))
    if side=='Left':preferred=reference['LeftForeArm'].translation.lerp(preferred,blend)
    pole = preferred - origin
    pole = (pole-axis*pole.dot(axis)).normalized()
    elbow = origin + axis*along + pole*math.sqrt(max(0, a*a-along*along))
    aim(side+'Arm', origin, elbow-origin)
    forearm = aim(side+'ForeArm', elbow, wrist-elbow)
    # Supinate the forearm and hand together: palm faces upward, with the wrist
    # still aligned to the forearm. Preserve the upper arm's reference roll.
    y = (wrist-elbow).normalized()
    current = forearm @ Vector((0, 0, -1))
    desired = (Vector((0, 0, 1))-y*y.z).normalized()
    current = (current-y*current.dot(y)).normalized()
    angle = math.atan2(y.dot(current.cross(desired)), current.dot(desired))
    forearm = Quaternion(y, angle*blend+math.radians(roll)) @ forearm
    rig.pose.bones[side+'ForeArm'].matrix = Matrix.LocRotScale(elbow, forearm, Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    relative=Quaternion((1,0,0),math.radians(-flex))
    if side=='Left':
        original=reference['LeftForeArm'].to_quaternion().inverted()@reference['LeftHand'].to_quaternion()
        relative=original.slerp(relative,blend)
    hand = forearm @ relative
    rig.pose.bones[side+'Hand'].matrix = Matrix.LocRotScale(wrist, hand, Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    return {'wrist': list(wrist), 'elbow': list(elbow), 'shoulder': list(origin), 'reach': distance/(a+b)}


def cradle_fingers(side='Right',grasp=0):
    # Small curls preserve broad-object support while the wrist and free hand
    # carry the larger gesture. Full closure needs an object-specific grip.
    grasp *= .5
    hand = rig.pose.bones[side+'Hand'].matrix.copy()
    q = hand.to_quaternion()
    # Rebuild a soft open cradle, rather than retaining the cylindrical torch
    # grip. Phalanges keep their original offsets and lengths.
    for finger, angles in [('Index', (5+3*grasp, 10+8*grasp, 15+10*grasp)), ('Middle', (5, 12, 19)),
                           ('Ring', (8+2*grasp, 14+5*grasp, 23+6*grasp)), ('Pinky', (11+4*grasp, 19+6*grasp, 28+8*grasp))]:
        for joint, angle in enumerate(angles, 1):
            bone = rig.pose.bones[f'{side}Hand{finger}{joint}']
            direction = q @ Vector((0, math.cos(math.radians(angle)), -math.sin(math.radians(angle))))
            old = bone.matrix.to_quaternion()
            rotation = (old @ Vector((0, 1, 0))).rotation_difference(direction) @ old
            bone.matrix = Matrix.LocRotScale(bone.head, rotation, Vector((1, 1, 1)))
            bpy.context.view_layer.update()
    sign = 1 if (hand.inverted() @ rig.pose.bones[side+'HandThumb1'].head).x > 0 else -1
    # Keep the thumb's support height stable while its tip subtly readjusts.
    # A large opposition curl would push it through a broad flat book.
    for joint, direction in enumerate([(sign*.65, .75, -.05), (sign*(.12-.04*grasp), .98, -.08-.02*grasp), (-sign*(.1+.045*grasp), .97, -.12-.02*grasp)], 1):
        bone = rig.pose.bones[f'{side}HandThumb{joint}']
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
    lift=0;support=0
    if motion == 'Hold':
        wrist += Vector((.003*math.sin(t*math.tau), .002*math.sin(t*math.tau), .004*math.sin(t*math.tau)))
        roll=2.5*math.sin(t*math.tau);flex=4+1.5*math.sin(t*math.tau)
        grasp=.3+.15*math.sin(t*math.tau+.5)
    elif motion == 'Equip':
        wrist = Vector((-.235, -.19, 1.08)).lerp(wrist, ease(t))
        roll=-6*(1-ease(t));flex=4*ease(t)
        grasp=(.3+.15*math.sin(.5))*ease(min(1,t/.7))
    else:
        # One continuous lift, short presentation, then return. This is an
        # item-agnostic gesture; no reading/eating game event is authored.
        lift = ease(t/.38) if t < .38 else (1 if t < .58 else 1-ease((t-.58)/.42))
        wrist = wrist.lerp(Vector((-.17, -.395, 1.515)), lift)
        wrist.x-=.008*math.sin(math.pi*t)**2
        roll=-6*lift;flex=4+6*lift
        grasp=(.3+.15*math.sin(.5))+.55*math.sin(math.pi*t)**2
        support=ease(t/.27) if t<.27 else (1 if t<.65 else 1-ease((t-.65)/.35))
    if lift>0:
        spine=rig.pose.bones['Spine2'];at=spine.matrix.copy()
        spine.matrix=Matrix.LocRotScale(at.translation,Quaternion((0,0,1),math.radians(2*lift))@at.to_quaternion(),Vector((1,1,1)))
        bpy.context.view_layer.update()
    record = articulated_arm('Right',wrist,roll,flex)
    cradle_fingers('Right',grasp)
    if support>0:
        target=Vector((.03,-.34,1.35)).lerp(Vector((-.01,-.36,1.48)),lift)
        left_wrist=reference['LeftHand'].translation.lerp(target,support)
        articulated_arm('Left',left_wrist,0,4,support)
        # A soft support pose approaches under the object, then releases it.
        cradle_fingers('Left',.25)
        for bone in rig.pose.bones:
            if not bone.name.startswith('LeftHand') or bone.name=='LeftHand':continue
            position,rotation,scale=base[bone.name].decompose()
            target_position,target_rotation,target_scale=bone.matrix_basis.decompose()
            bone.matrix_basis=Matrix.LocRotScale(position.lerp(target_position,support),rotation.slerp(target_rotation,support),scale.lerp(target_scale,support))
        bpy.context.view_layer.update()
    record.update({'wrist_flex_degrees':flex,'palm_roll_degrees':roll,'grasp':grasp,'support':support})
    return record


actions = {}
records = {}
for motion, count in [('Hold', 144), ('Equip', 36), ('Use', 96)]:
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

# Fit a single rigid mount against the articulated hand's swept skin envelope.
# The object must not slide when the fingers adjust between these poses.
names = {group.index: group.name for group in body.vertex_groups}
weighted = []
for vertex in body.data.vertices:
    groups = [(names[g.group], g.weight) for g in vertex.groups if names[g.group] in reference]
    if sum(weight for name, weight in groups if name.startswith('RightHand')) < .8:
        continue
    weighted.append((vertex.co.copy(), groups))
envelope = {}
for motion, frames in [('Hold', [0, 36, 72, 108, 144]), ('Equip', [0, 18, 36]), ('Use', [0, 24, 48, 72, 96])]:
    rig.animation_data.action = actions[motion]
    if actions[motion].slots:
        rig.animation_data.action_slot = actions[motion].slots[0]
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        inverse = rig.pose.bones['RightHand'].matrix.inverted()
        palette = {b.name: b.matrix @ b.bone.matrix_local.inverted() for b in rig.pose.bones}
        for point, groups in weighted:
            posed = inverse @ sum(((palette[name] @ point)*weight for name, weight in groups), Vector((0, 0, 0)))
            if -.10 < posed.x < .10 and -.01 < posed.y < .24:
                envelope[tuple(round(c, 6) for c in posed)] = list(posed)
hand_points = list(envelope.values())
support = float(np.array(hand_points)[:, 2].min()) - .0015
scene.render.fps = 60
scene.frame_start = 0
scene.frame_end = 120
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.item_use_v2.glb'), export_format='GLB', use_selection=True,
                         export_materials='NONE', export_animations=True, export_animation_mode='ACTIONS',
                         export_frame_range=False, export_force_sampling=True, export_skins=True,
                         export_morph=False, export_yup=True)
bpy.context.preferences.filepaths.save_version = 0
# Save beside the destination under a unique name, then atomically replace it.
# Windows file watchers can briefly lock a just-written Blender destination.
temporary = OUT/('Human.item_use_v2.tmp.'+uuid.uuid4().hex+'.blend')
bpy.ops.wm.save_as_mainfile(filepath=str(temporary), compress=True)
for attempt in range(20):
    try:
        os.replace(temporary, OUT/'Human.item_use_v2.blend')
        break
    except PermissionError:
        if attempt == 19:
            raise
        time.sleep(.1)
metadata = {'status': 'Review-only revision 02; player acceptance required before integration',
            'creator': 'TerraForest original AI-assisted motion authoring with OpenAI Codex',
            'license': 'CC0-1.0 new motion; inherited R11 rig/body/carry notices retained',
            'source': source.relative_to(ROOT).as_posix(), 'source_sha256': source_hash,
            'tool': 'Blender '+bpy.app.version_string, 'fps': 60,
            'prompt': 'Improve the committed baseline after feedback that the hand looks like a static stick: add finger readjustments, wrist articulation and free-hand support. Keep this revision outside gameplay pending review.',
            'actions': records, 'support_plane_hand_z': support, 'support_center_hand_y': .055,
            'support_vertices': len(hand_points), 'support_samples_hand': hand_points, 'external_motion': None,
            'demo_items': ['Existing CC0 field-manual mesh 214', 'Existing CC0 trail-bread mesh 218', 'Original neutral box proxy'],
            'scope': 'Pose-only, no item consumption, reading reward, damage, save/input or gameplay dispatch changes'}
(OUT/'Human.item_use_v2.json').write_text(json.dumps(metadata, indent=2)+'\n')
print('ITEM_USE_AUTHORED support_plane=', support, 'vertices=', len(hand_points))
