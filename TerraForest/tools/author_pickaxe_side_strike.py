# SPDX-License-Identifier: 0BSD
"""A separate side-strike copy of preserved v4, with the same ready grip."""
import hashlib
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'addons/characters/authoring'
source = Path(bpy.data.filepath)
assert source.name == 'Human.pickaxe_diagonal.blend'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
assert source_hash == 'fc19d70c8209b01f996e2658ccf2f424b93fb766928e27a3c3a2caba3ddd8351', 'Use the preserved v4, not an experiment'
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
kept = bpy.data.actions['FP_Pickaxe_Diagonal_Swing']


def select(action, frame):
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(frame)
    bpy.context.view_layer.update()


select(kept, 0)
ready_local = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
ready_global = {b.name: b.matrix.copy() for b in rig.pose.bones}
ready_tool = ready_global['Weapon_Pickaxe']
grips = {side: ready_tool.inverted() @ ready_global[side+'Hand'] for side in ['Left', 'Right']}
source_rotation = Quaternion((1, 0, 0), -.35) @ Quaternion((0, 1, 0), math.radians(38)) @ ready_tool.to_quaternion()
TIP = Vector((-.326, 0, .535))


def rotation(lean, pitch):
    return Quaternion((0, 1, 0), -math.radians(lean)) @ Quaternion((1, 0, 0), pitch) @ source_rotation


def aimed(target, lean, pitch):
    return tuple(Vector(target)-rotation(lean, pitch) @ TIP)


# Blender -X = player right; -Y = forward. Wind-up stays beside the player,
# then the point advances diagonally at near-constant target height. The shaft
# continues leaning right throughout the stroke; the torso stays at ready.
KEYS = [(0, tuple(ready_tool.translation), 38, .35),
        (12, (-.07, -.43, 1.30), 55, .27),
        (20, (-.10, -.35, 1.31), 65, .25),
        (26, aimed((-.35, -.90, 1.62), 55, .45), 55, .45),
        (32, aimed((-.14, -1.025, 1.64), 40, .62), 40, .62),
        (38, aimed((-.07, -1.045, 1.60), 35, .64), 35, .64),
        (44, aimed((-.09, -1.01, 1.60), 36, .60), 36, .60),
        (56, (-.05, -.49, 1.29), 40, .43),
        (72, tuple(ready_tool.translation), 38, .35)]


def parameters(frame):
    values = [[*key[1], *key[2:]] for key in KEYS]
    def tangent(i, c):
        if i == 0 or i == len(KEYS)-1:
            return 0.0
        a = (values[i][c]-values[i-1][c])/(KEYS[i][0]-KEYS[i-1][0])
        b = (values[i+1][c]-values[i][c])/(KEYS[i+1][0]-KEYS[i][0])
        return 2*a*b/(a+b) if a*b > 0 else 0.0
    for i, (a, b) in enumerate(zip(KEYS, KEYS[1:])):
        if a[0] <= frame <= b[0]:
            interval = b[0]-a[0]
            t = (frame-a[0])/interval
            result = [(2*t*t*t-3*t*t+1)*values[i][c]+(t*t*t-2*t*t+t)*interval*tangent(i, c)
                      +(-2*t*t*t+3*t*t)*values[i+1][c]+(t*t*t-t*t)*interval*tangent(i+1, c) for c in range(5)]
            return Vector(result[:3]), *result[3:]
    raise ValueError(frame)


def orient(name, head, direction, reference):
    previous = reference.to_quaternion()
    q = (previous @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ previous
    rig.pose.bones[name].matrix = Matrix.LocRotScale(head, q, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def solve_arm(side, target, tool):
    origin = rig.pose.bones[side+'Arm'].head.copy()
    wrist = target.translation
    upper = rig.data.bones[side+'Arm'].length
    lower = rig.data.bones[side+'ForeArm'].length
    delta = wrist-origin
    distance = delta.length
    assert abs(upper-lower)+.001 < distance < upper+lower-.001, (side, scene.frame_current, distance, upper+lower, list(wrist))
    axis = delta.normalized()
    along = (upper*upper-lower*lower+distance*distance)/(2*distance)
    ref_elbow = ready_global[side+'ForeArm'].translation-origin
    pole = (ref_elbow-axis*ref_elbow.dot(axis)).normalized()
    elbow = origin+axis*along+pole*math.sqrt(max(0, upper*upper-along*along))
    orient(side+'Arm', origin, elbow-origin, ready_global[side+'Arm'])
    # Carry forearm roll with the held tool instead of concentrating it at wrist.
    relative = ready_tool.inverted() @ ready_global[side+'ForeArm']
    orient(side+'ForeArm', elbow, wrist-elbow, tool @ relative)
    rig.pose.bones[side+'Hand'].matrix = target
    bpy.context.view_layer.update()
    return {'reach_fraction': distance/(upper+lower), 'wrist_error_m': (rig.pose.bones[side+'Hand'].head-wrist).length}


action = kept.copy()
action.name = 'FP_Pickaxe_SideStrike_Swing'
action.use_fake_user = True
select(action, 0)
records = []
for frame in range(73):
    scene.frame_set(frame)
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.matrix_basis = ready_local[bone.name]
    bpy.context.view_layer.update()
    pivot, lean, pitch = parameters(frame)
    tool = Matrix.LocRotScale(pivot, rotation(lean, pitch), Vector((1, 1, 1)))
    reach = {}
    if frame not in [0, 72]:
        rig.pose.bones['Weapon_Pickaxe'].matrix = tool
        bpy.context.view_layer.update()
        reach = {side: solve_arm(side, tool @ grips[side], tool) for side in ['Left', 'Right']}
    for bone in rig.pose.bones:
        bone.keyframe_insert('location', frame=frame, group=bone.name)
        bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
        bone.keyframe_insert('scale', frame=frame, group=bone.name)
    records.append({'frame': frame, 'pivot': list(pivot), 'working_tip': list(tool @ TIP),
                    'head': list(tool @ Vector((0, 0, .60))), 'right_lean_degrees': lean,
                    'tool_quaternion_wxyz': list(tool.to_quaternion()), 'reach': reach})
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:
                    key.interpolation = 'LINEAR'
action.use_frame_range = True
action.frame_start, action.frame_end = 0, 72
scene.frame_start, scene.frame_end, scene.render.fps = 0, 72, 60
scene.timeline_markers.clear()
for label, frame in [('PRESERVED READY', 0), ('DRAW BACK BESIDE RIGHT SHOULDER', 20), ('DRIVE FROM THE SIDE', 26), ('FORWARD DIAGONAL CONTACT', 32), ('SHORT FOLLOW THROUGH', 38), ('RECOVER', 56), ('PRESERVED READY', 72)]:
    scene.timeline_markers.new(label, frame=frame)
rig['pickaxe_description'] = 'SEPARATE SIDE-STRIKE REVIEW: copied from preserved v4. Same ready grip, lower side wind-up, forward right-to-left diagonal approach, shaft remains angled right, neutral torso, short continuation and recovery. No commit.'
select(action, 0)
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.pickaxe_side_strike.glb'), export_format='GLB',
    use_selection=True, export_materials='NONE', export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=False, export_force_sampling=True, export_skins=True, export_morph=False, export_yup=True)
report = {'approval': 'PENDING USER VISUAL REVIEW; do not commit', 'source': str(source.relative_to(ROOT)),
          'source_sha256': source_hash, 'action': action.name, 'fps': 60, 'duration': 1.2,
          'revision': 'Side wind-up and forward diagonal strike; preserved ready pose; neutral torso',
          'samples': records}
(OUT/'Human.pickaxe_side_strike.json').write_text(json.dumps(report, indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.pickaxe_side_strike.blend'), compress=True)
print('PICKAXE_SIDE_STRIKE_AUTHORED', json.dumps({k:v for k,v in report.items() if k!='samples'}))
