# SPDX-License-Identifier: 0BSD
"""Test copy: lower-hand-led arc swing with a restrained rightward tool tilt."""
import hashlib
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'addons/characters/authoring'
source = Path(bpy.data.filepath)
assert source.name == 'Human.pickaxe_side_pullback.blend'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
manifest = json.loads((ROOT/'docs/evidence/pickaxe_arc_swing/baseline_preserved.json').read_text())
assert source_hash == manifest['addons/characters/authoring/Human.pickaxe_side_pullback.blend']
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
kept = bpy.data.actions['FP_Pickaxe_SidePullback_Swing']
END = 72
RIGHT_BIAS_DEGREES = 5.0


def select(action, frame):
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(frame)
    bpy.context.view_layer.update()


baseline = []
for frame in range(END+1):
    select(kept, frame)
    baseline.append(({b.name: b.matrix_basis.copy() for b in rig.pose.bones},
                     {b.name: b.matrix.copy() for b in rig.pose.bones}))
ready_local, ready_global = baseline[0]
ready_tool = ready_global['Weapon_Pickaxe']
grips = {side: ready_tool.inverted() @ ready_global[side+'Hand'] for side in ['Left', 'Right']}
source_rotation = Quaternion((1, 0, 0), -.35) @ Quaternion((0, 1, 0), math.radians(38)) @ ready_tool.to_quaternion()
TIP = Vector((-.326, 0, .535))


def smooth(t):
    return t*t*(3-2*t)


def curve(keys, frame):
    def slope(i):
        if i == 0 or i == len(keys)-1:
            return 0.0
        a = (keys[i][1]-keys[i-1][1])/(keys[i][0]-keys[i-1][0])
        b = (keys[i+1][1]-keys[i][1])/(keys[i+1][0]-keys[i][0])
        return 2*a*b/(a+b) if a*b > 0 else 0.0
    for i, (a, b) in enumerate(zip(keys, keys[1:])):
        if a[0] <= frame <= b[0]:
            dt = b[0]-a[0]
            t = (frame-a[0])/dt
            return (2*t**3-3*t*t+1)*a[1]+(t**3-2*t*t+t)*dt*slope(i)+(-2*t**3+3*t*t)*b[1]+(t**3-t*t)*dt*slope(i+1)
    raise ValueError(frame)


def bias(frame):
    return RIGHT_BIAS_DEGREES*curve([(0, 0), (12, 1), (48, 1), (72, 0)], frame)


def rotation(frame):
    lean = curve([(0, 38), (12, 60), (20, 65), (32, 40), (40, 35), (54, 42), (72, 38)], frame)
    pitch = curve([(0, .35), (12, .12), (20, -.12), (32, .62), (40, .78), (54, .52), (72, .35)], frame)
    return Quaternion((0, 1, 0), -math.radians(lean+bias(frame))) @ Quaternion((1, 0, 0), pitch) @ source_rotation


# Keep the useful forward contact location from the liked copy. Rotation about
# the lower grip now supplies most of the forward head travel, while that grip
# follows a shallow ellipse instead of extending straight toward the target.
contact_tip = baseline[32][1]['Weapon_Pickaxe'] @ TIP
contact_anchor = contact_tip-rotation(32) @ (TIP-grips['Left'].translation)
center = contact_anchor+Vector((0, .10, 0))
ready_anchor = ready_global['LeftHand'].translation


def attack_anchor(frame):
    angle = math.radians(curve([(20, -90), (32, 0), (40, 24)], frame))
    point = center+Vector((.20*math.sin(angle), -.10*math.cos(angle), 0))
    point.z = curve([(20, contact_anchor.z-.08), (32, contact_anchor.z), (40, contact_anchor.z-.075)], frame)
    return point


chamber_anchor, follow_anchor = attack_anchor(20), attack_anchor(40)


def bezier(a, b, c, d, t):
    return a*(1-t)**3+b*(3*(1-t)**2*t)+c*(3*(1-t)*t*t)+d*t**3


def anchor(frame):
    if frame < 20:
        t = smooth(frame/20)
        return bezier(ready_anchor, ready_anchor+Vector((-.10, .015, -.025)),
                      chamber_anchor+Vector((-.035, -.09, -.015)), chamber_anchor, t)
    if frame <= 40:
        return attack_anchor(frame)
    t = smooth((frame-40)/32)
    # A lower curved return, rather than rewinding the outbound line.
    return bezier(follow_anchor, follow_anchor+Vector((.015, .10, -.15)),
                  ready_anchor+Vector((-.10, .10, -.10)), ready_anchor, t)


def orient(name, head, direction, reference):
    previous = reference.to_quaternion()
    q = (previous @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ previous
    rig.pose.bones[name].matrix = Matrix.LocRotScale(head, q, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def solve(side, target, tool):
    origin = rig.pose.bones[side+'Arm'].head.copy()
    wrist = target.translation
    upper, lower = rig.data.bones[side+'Arm'].length, rig.data.bones[side+'ForeArm'].length
    delta = wrist-origin
    distance = delta.length
    assert abs(upper-lower)+.001 < distance < upper+lower-.001, (side, scene.frame_current, distance, upper+lower, list(wrist))
    axis = delta.normalized()
    along = (upper*upper-lower*lower+distance*distance)/(2*distance)
    elbow_reference = ready_global[side+'ForeArm'].translation-origin
    pole = (elbow_reference-axis*elbow_reference.dot(axis)).normalized()
    elbow = origin+axis*along+pole*math.sqrt(max(0, upper*upper-along*along))
    orient(side+'Arm', origin, elbow-origin, ready_global[side+'Arm'])
    orient(side+'ForeArm', elbow, wrist-elbow, tool @ (ready_tool.inverted() @ ready_global[side+'ForeArm']))
    rig.pose.bones[side+'Hand'].matrix = target
    bpy.context.view_layer.update()
    return {'reach_fraction': distance/(upper+lower), 'wrist_error_m': (rig.pose.bones[side+'Hand'].head-wrist).length}


action = kept.copy()
action.name = 'FP_Pickaxe_ArcSwing_Swing'
action.use_fake_user = True
select(action, 0)
records = []
for frame in range(END+1):
    scene.frame_set(frame)
    for bone in rig.pose.bones:
        bone.matrix_basis = ready_local[bone.name]
    bpy.context.view_layer.update()
    q = rotation(frame)
    pivot = anchor(frame)-q @ grips['Left'].translation
    tool = Matrix.LocRotScale(pivot, q, Vector((1, 1, 1)))
    reach = {}
    if frame not in [0, END]:
        rig.pose.bones['Weapon_Pickaxe'].matrix = tool
        bpy.context.view_layer.update()
        reach = {side: solve(side, tool @ grips[side], tool) for side in ['Left', 'Right']}
    for bone in rig.pose.bones:
        bone.keyframe_insert('location', frame=frame, group=bone.name)
        bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
        bone.keyframe_insert('scale', frame=frame, group=bone.name)
    records.append({'frame': frame, 'pivot': list(pivot), 'lower_grip': list(anchor(frame)),
                    'working_tip': list(tool @ TIP), 'head': list(tool @ Vector((0, 0, .60))),
                    'right_bias_degrees': bias(frame), 'tool_quaternion_wxyz': list(q), 'reach': reach})
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for channel in bag.fcurves:
                for key in channel.keyframe_points:
                    key.interpolation = 'LINEAR'
action.use_frame_range = True
action.frame_start, action.frame_end = 0, END
scene.frame_start, scene.frame_end, scene.render.fps = 0, END, 60
scene.timeline_markers.clear()
for label, frame in [('KEPT READY', 0), ('CURVED WINDUP', 12), ('SWING BACK', 20), ('SWING THROUGH TARGET', 32), ('CONTINUE ARC', 40), ('CURVED RECOVERY', 54), ('KEPT READY', END)]:
    scene.timeline_markers.new(label, frame=frame)
rig['pickaxe_description'] = 'TEST COPY from liked deeper pullback: 5-degree right bias, rotational side swing about lower grip, shallow elliptical grip travel, curved recovery, neutral torso. Kept ready endpoints. Do not commit.'
select(action, 0)
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.pickaxe_arc_swing.glb'), export_format='GLB',
    use_selection=True, export_materials='NONE', export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=False, export_force_sampling=True, export_skins=True, export_morph=False, export_yup=True)
report = {'approval': 'PENDING USER VISUAL REVIEW; do not commit', 'source': str(source.relative_to(ROOT)),
          'source_sha256': source_hash, 'action': action.name, 'fps': 60, 'duration': 1.2,
          'right_bias_degrees': RIGHT_BIAS_DEGREES, 'contact_target_blender': list(contact_tip),
          'revision': 'Curved wind-up, lower-grip-led rotational strike and curved recovery; neutral torso; kept ready endpoints',
          'samples': records}
(OUT/'Human.pickaxe_arc_swing.json').write_text(json.dumps(report, indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.pickaxe_arc_swing.blend'), compress=True)
print('PICKAXE_ARC_SWING_AUTHORED', json.dumps({k:v for k,v in report.items() if k!='samples'}))
