# SPDX-License-Identifier: 0BSD
"""Duplicate the kept v4 Blender action; change only its post-contact follow-through."""
import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'addons/characters/authoring'
REPORT = ROOT / 'reports/pickaxe_left_follow'
REPORT.mkdir(parents=True, exist_ok=True)
source = Path(bpy.data.filepath)
assert source.name == 'Human.pickaxe_diagonal.blend', 'Start from the kept v4 blend'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
kept = bpy.data.actions['FP_Pickaxe_Diagonal_Swing']
PREFIX = 'FP_Pickaxe_LeftFollow_'
CONTACT, FINISH, END = 32, 48, 72


def select(action, frame):
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(frame)
    bpy.context.view_layer.update()


def snapshot(frame):
    select(kept, frame)
    return ({b.name: b.matrix_basis.copy() for b in rig.pose.bones},
            {b.name: b.matrix.copy() for b in rig.pose.bones})


baseline = [snapshot(frame) for frame in range(END+1)]
contact_local, contact_global = baseline[CONTACT]
ready_local, ready_global = baseline[END]
tool_name = 'Weapon_Pickaxe'
contact_tool = contact_global[tool_name]
ready_tool = ready_global[tool_name]
grips = {side: contact_tool.inverted() @ contact_global[side+'Hand'] for side in ['Left', 'Right']}
# The kept action is copied, including all original finger, body and tool keys.
action = kept.copy()
action.name = PREFIX+'Swing'
action.use_fake_user = True
select(action, CONTACT)


def smooth(t):
    return t*t*(3-2*t)


def hermite(a, b, va, vb, t):
    return a*(2*t*t*t-3*t*t+1)+va*(t*t*t-2*t*t+t)+b*(-2*t*t*t+3*t*t)+vb*(t*t*t-t*t)


def set_local(poses):
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.matrix_basis = poses[bone.name]
    bpy.context.view_layer.update()


def orient_from_reference(name, position, direction, reference):
    previous = reference.to_quaternion()
    rotation = (previous @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ previous
    rig.pose.bones[name].matrix = Matrix.LocRotScale(position, rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def solve_arm(side, hand, references):
    # Keep the copied shoulder and torso pose. Bend each elbow on its valid
    # two-bone circle, transporting the copied elbow direction and bone roll.
    origin = rig.pose.bones[side+'Arm'].head.copy()
    wrist = hand.translation
    upper = rig.data.bones[side+'Arm'].length
    lower = rig.data.bones[side+'ForeArm'].length
    delta = wrist-origin
    distance = delta.length
    assert abs(upper-lower)+.001 < distance < upper+lower-.001, (side, scene.frame_current, distance, upper+lower, list(origin), list(wrist))
    axis = delta.normalized()
    along = (upper*upper-lower*lower+distance*distance)/(2*distance)
    prior_elbow = references[side+'ForeArm'].translation-origin
    pole = (prior_elbow-axis*prior_elbow.dot(axis)).normalized()
    elbow = origin+axis*along+pole*math.sqrt(max(0, upper*upper-along*along))
    orient_from_reference(side+'Arm', origin, elbow-origin, references[side+'Arm'])
    orient_from_reference(side+'ForeArm', elbow, wrist-elbow, references[side+'ForeArm'])
    rig.pose.bones[side+'Hand'].matrix = hand
    bpy.context.view_layer.update()
    return {'reach_fraction': distance/(upper+lower), 'wrist_error_m': (rig.pose.bones[side+'Hand'].head-wrist).length}


# Blender +X is player left. Keep depth at the forward contact, avoiding the
# rejected experiment's pull toward the camera. Descend as the head passes left.
offset = Vector((.36, .06, -.09))
finish_tool = contact_tool.copy()
finish_tool.translation += offset
incoming = (contact_tool.translation-baseline[CONTACT-1][1][tool_name].translation)*(FINISH-CONTACT)
rows = []
for frame in range(CONTACT+1, END):
    scene.frame_set(frame)
    if frame <= FINISH:
        t = (frame-CONTACT)/(FINISH-CONTACT)
        set_local(contact_local)
        tool = contact_tool.copy()
        tool.translation = hermite(contact_tool.translation, finish_tool.translation, incoming, Vector((0, 0, 0)), t)
        references = contact_global
    else:
        t = smooth((frame-FINISH)/(END-FINISH))
        # Recover separately to the exact original ready pose. The body returns
        # toward neutral; it never acquires an additional leftward turn.
        set_local({name: contact_local[name].lerp(ready_local[name], t) for name in contact_local})
        tool = finish_tool.lerp(ready_tool, t)
        references = {name: contact_global[name].lerp(ready_global[name], t) for name in contact_global}
    rig.pose.bones[tool_name].matrix = tool
    bpy.context.view_layer.update()
    reach = {side: solve_arm(side, tool @ grips[side], references) for side in ['Left', 'Right']}
    for bone in rig.pose.bones:
        bone.keyframe_insert('location', frame=frame, group=bone.name)
        bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
        bone.keyframe_insert('scale', frame=frame, group=bone.name)
    rows.append({'frame': frame, 'pivot': list(tool.translation), 'tool_quaternion_wxyz': list(tool.to_quaternion()), 'reach': reach})

for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:
                    key.interpolation = 'LINEAR'
action.use_frame_range = True
action.frame_start, action.frame_end = 0, END

def matrix_error(a, b):
    return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4))

preserved_error = 0.0
rotation_error = 0.0
body_error = 0.0
for frame in range(END+1):
    select(action, frame)
    if frame <= CONTACT or frame == END:
        for bone in rig.pose.bones:
            preserved_error = max(preserved_error, matrix_error(bone.matrix_basis, baseline[frame][0][bone.name]))
    if CONTACT <= frame <= FINISH:
        rotation_error = max(rotation_error, math.degrees(rig.pose.bones[tool_name].matrix.to_quaternion().rotation_difference(contact_tool.to_quaternion()).angle))
        for name in ['Root', 'Spine', 'Spine1', 'Spine2']:
            body_error = max(body_error, matrix_error(rig.pose.bones[name].matrix, contact_global[name]))
assert preserved_error < .00001, preserved_error
assert rotation_error < .05, rotation_error
assert body_error < .00001, body_error

# Export only this new action; retain the kept actions inside the editable copy.
others = [item for item in bpy.data.actions if item != action]
for item in others:
    item.use_fake_user = False
select(action, 0)
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUTPUT/'Human.pickaxe_left_follow.glb'), export_format='GLB',
    use_selection=True, export_materials='NONE', export_animations=True,
    export_animation_mode='ACTIONS', export_frame_range=False, export_force_sampling=True,
    export_skins=True, export_morph=False, export_yup=True)
for item in others:
    item.use_fake_user = True
scene.frame_start, scene.frame_end, scene.render.fps = 0, END, 60
scene.timeline_markers.clear()
for label, frame in [('KEPT READY', 0), ('KEPT WINDUP', 20), ('KEPT FORWARD CONTACT', CONTACT), ('LEFT FOLLOW THROUGH - NO EXTRA TWIST', FINISH), ('KEPT READY AGAIN', END)]:
    scene.timeline_markers.new(label, frame=frame)
rig['pickaxe_description'] = 'SEPARATE REVIEW COPY: exact kept v4 frames 0-32, forward contact then left/down continuation with fixed tool and torso orientation through frame 48. Original ready at 72. Do not commit.'
report = {'approval': 'PENDING USER VISUAL REVIEW; do not commit', 'source': str(source.relative_to(ROOT)),
          'source_sha256': source_hash, 'action': action.name, 'fps': 60, 'duration': 1.2,
          'preserved_frames': [0, CONTACT], 'fixed_orientation_frames': [CONTACT, FINISH],
          'continuation_offset_blender_m': list(offset), 'preserved_pose_max_error': preserved_error,
          'continuation_tool_rotation_error_degrees': rotation_error, 'continuation_body_matrix_error': body_error,
          'samples': rows}
(OUTPUT/'Human.pickaxe_left_follow.json').write_text(json.dumps(report, indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT/'Human.pickaxe_left_follow.blend'), compress=True)
print('PICKAXE_LEFT_FOLLOW_AUTHORED', json.dumps({k: v for k, v in report.items() if k != 'samples'}))
