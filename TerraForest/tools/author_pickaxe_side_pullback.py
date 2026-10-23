# SPDX-License-Identifier: 0BSD
"""Copy the liked side strike, adding only a modest deeper preparatory pullback."""
import hashlib
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'addons/characters/authoring'
source = Path(bpy.data.filepath)
assert source.name == 'Human.pickaxe_side_strike.blend'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
manifest = json.loads((ROOT/'docs/evidence/pickaxe_side_pullback/baseline_preserved.json').read_text())
assert source_hash == manifest['addons/characters/authoring/Human.pickaxe_side_strike.blend']
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
kept = bpy.data.actions['FP_Pickaxe_SideStrike_Swing']
BEGIN, PEAK, REJOIN, END = 4, 20, 28, 72
EXTRA_PULLBACK = .08  # Blender +Y is toward the player.


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


def smooth(t):
    return t*t*(3-2*t)


def extra(frame):
    if frame <= BEGIN or frame >= REJOIN:
        return 0.0
    if frame <= PEAK:
        return EXTRA_PULLBACK*smooth((frame-BEGIN)/(PEAK-BEGIN))
    return EXTRA_PULLBACK*(1-smooth((frame-PEAK)/(REJOIN-PEAK)))


def orient(name, position, direction, reference):
    q = reference.to_quaternion()
    q = (q @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ q
    rig.pose.bones[name].matrix = Matrix.LocRotScale(position, q, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def solve(side, target, reference):
    origin = rig.pose.bones[side+'Arm'].head.copy()
    wrist = target.translation
    upper = rig.data.bones[side+'Arm'].length
    lower = rig.data.bones[side+'ForeArm'].length
    delta = wrist-origin
    distance = delta.length
    assert abs(upper-lower)+.001 < distance < upper+lower-.001, (side, scene.frame_current, distance)
    axis = delta.normalized()
    along = (upper*upper-lower*lower+distance*distance)/(2*distance)
    old_elbow = reference[side+'ForeArm'].translation-origin
    pole = (old_elbow-axis*old_elbow.dot(axis)).normalized()
    elbow = origin+axis*along+pole*math.sqrt(max(0, upper*upper-along*along))
    orient(side+'Arm', origin, elbow-origin, reference[side+'Arm'])
    orient(side+'ForeArm', elbow, wrist-elbow, reference[side+'ForeArm'])
    rig.pose.bones[side+'Hand'].matrix = target
    bpy.context.view_layer.update()
    return {'reach_fraction': distance/(upper+lower), 'wrist_error_m': (rig.pose.bones[side+'Hand'].head-wrist).length}


action = kept.copy()
action.name = 'FP_Pickaxe_SidePullback_Swing'
action.use_fake_user = True
select(action, 0)
records = []
for frame in range(BEGIN+1, REJOIN):
    scene.frame_set(frame)
    local, original = baseline[frame]
    for bone in rig.pose.bones:
        bone.matrix_basis = local[bone.name]
    bpy.context.view_layer.update()
    offset = Vector((0, extra(frame), 0))
    tool = original['Weapon_Pickaxe'].copy()
    tool.translation += offset
    rig.pose.bones['Weapon_Pickaxe'].matrix = tool
    bpy.context.view_layer.update()
    reach = {}
    for side in ['Left', 'Right']:
        target = original[side+'Hand'].copy()
        target.translation += offset
        reach[side] = solve(side, target, original)
    for bone in rig.pose.bones:
        bone.keyframe_insert('location', frame=frame, group=bone.name)
        bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
        bone.keyframe_insert('scale', frame=frame, group=bone.name)
    records.append({'frame': frame, 'extra_pullback_m': extra(frame), 'pivot': list(tool.translation), 'reach': reach})
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:
                    key.interpolation = 'LINEAR'


def error(a, b):
    return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4))


preserved_error, body_error, tool_orientation_error = 0.0, 0.0, 0.0
for frame in range(END+1):
    select(action, frame)
    local, original = baseline[frame]
    if frame <= BEGIN or frame >= REJOIN:
        for bone in rig.pose.bones:
            preserved_error = max(preserved_error, error(bone.matrix_basis, local[bone.name]))
    for name in ['Root', 'Spine', 'Spine1', 'Spine2']:
        body_error = max(body_error, error(rig.pose.bones[name].matrix, original[name]))
    tool_orientation_error = max(tool_orientation_error, math.degrees(
        rig.pose.bones['Weapon_Pickaxe'].matrix.to_quaternion().rotation_difference(original['Weapon_Pickaxe'].to_quaternion()).angle))
assert preserved_error < .00001 and body_error < .00001 and tool_orientation_error < .05
action.use_frame_range = True
action.frame_start, action.frame_end = 0, END
scene.frame_start, scene.frame_end, scene.render.fps = 0, END, 60
scene.timeline_markers.clear()
for label, frame in [('KEPT READY', 0), ('DEEPER PULLBACK', PEAK), ('REJOIN KEPT STRIKE', REJOIN), ('KEPT CONTACT', 32), ('KEPT FOLLOW THROUGH', 38), ('KEPT RECOVERY', 56), ('KEPT READY', END)]:
    scene.timeline_markers.new(label, frame=frame)
rig['pickaxe_description'] = 'SEPARATE COPY of liked side strike: additional 8 cm pull toward player before launch, same tool orientation and neutral body; rejoins kept action at frame 28. Contact/recovery/ready unchanged. Do not commit.'
select(action, 0)
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'Human.pickaxe_side_pullback.glb'), export_format='GLB',
    use_selection=True, export_materials='NONE', export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=False, export_force_sampling=True, export_skins=True, export_morph=False, export_yup=True)
report = {'approval': 'PENDING USER VISUAL REVIEW; do not commit', 'source': str(source.relative_to(ROOT)),
          'source_sha256': source_hash, 'action': action.name, 'duration': 1.2, 'fps': 60,
          'extra_pullback_m': EXTRA_PULLBACK, 'changed_frames': [BEGIN+1, REJOIN-1],
          'preserved_pose_error': preserved_error, 'body_error': body_error,
          'tool_orientation_error_degrees': tool_orientation_error, 'samples': records}
(OUT/'Human.pickaxe_side_pullback.json').write_text(json.dumps(report, indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Human.pickaxe_side_pullback.blend'), compress=True)
print('PICKAXE_SIDE_PULLBACK_AUTHORED', json.dumps({k:v for k,v in report.items() if k!='samples'}))
