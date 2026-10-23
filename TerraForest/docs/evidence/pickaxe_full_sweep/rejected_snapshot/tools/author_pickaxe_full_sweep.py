# SPDX-License-Identifier: 0BSD
"""Blender: separate full right-to-left swing, with fixed tool orientation during crossover."""
import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'addons/characters/authoring'
REPORT = ROOT / 'reports/pickaxe_full_sweep'
OUTPUT.mkdir(parents=True, exist_ok=True)
REPORT.mkdir(parents=True, exist_ok=True)
source = Path(bpy.data.filepath)
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
FPS = 60
PREFIX = 'FP_Pickaxe_FullSweep_'


def sample(action, frame):
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(int(frame), subframe=frame-int(frame))
    bpy.context.view_layer.update()
    return {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}


original = bpy.data.actions['FP_Pickaxe_RightGrip_Idle']
base = sample(original, 1.0)
source_tool = rig.pose.bones['Weapon_Pickaxe'].matrix.copy()
# Preserve the source's fitted right-upper/left-lower hand wraps as rigid
# transforms relative to the tool, including the original opposed thumbs.
grips = {side: source_tool.inverted() @ rig.pose.bones[side+'Hand'].matrix
         for side in ['Left', 'Right']}
rest_tool = rig.data.bones['Weapon_Pickaxe'].matrix_local.copy()
source_rotation = source_tool.to_quaternion()
arm_references = {side: {part: source_rotation.inverted() @ rig.pose.bones[side+part].matrix.to_quaternion()
                         for part in ['Arm', 'ForeArm']} for side in ['Left', 'Right']}
durations = {'Swing': 1.2, 'Idle': 3.0, 'Walk': 1.0, 'Run': .8, 'Jump': 1.5}
lower_poses = {}
for motion in ['Walk', 'Run', 'Jump']:
    action = bpy.data.actions['FP_Pickaxe_RightGrip_'+motion]
    start, end = action.frame_range
    count = round(durations[motion]*FPS)
    lower_poses[motion] = [sample(action, start+(end-start)*i/count) for i in range(count+1)]

for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type == 'MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            if key.name != 'Basis':
                key.value = 0.0
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)


def orient(name, head, direction, roll_reference=None):
    bone = rig.pose.bones[name]
    rest = rig.data.bones[name].matrix_local.to_quaternion()
    rotation = (rest @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ rest
    if roll_reference is not None:
        y = direction.normalized()
        x = (roll_reference-y*roll_reference.dot(y)).normalized()
        rotation = Matrix((x, y, x.cross(y))).transposed().to_quaternion()
    bone.matrix = Matrix.LocRotScale(head, rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def arm(side, hand_matrix, tool_rotation):
    shoulder = rig.pose.bones[side+'Shoulder'].head.copy()
    sign = 1 if side == 'Left' else -1
    orient(side+'Shoulder', shoulder, Vector((sign*.14, -.08, -.018)))
    origin = rig.pose.bones[side+'Arm'].head.copy()
    wrist = hand_matrix.translation
    upper = rig.data.bones[side+'Arm'].length
    lower = rig.data.bones[side+'ForeArm'].length
    delta = wrist-origin
    distance = delta.length
    if distance >= upper+lower-.001:
        raise ValueError(f'{side} unreachable at {scene.frame_current}: {distance:.4f} > {upper+lower:.4f}; wrist={list(wrist)} shoulder={list(origin)}')
    axis = delta.normalized()
    along = (upper*upper-lower*lower+distance*distance)/(2*distance)
    natural = Vector((sign*.47, -.12, 1.16))-origin
    natural = (natural-axis*natural.dot(axis)).normalized()
    # Choose the elbow around its valid IK circle to keep the wrist near its
    # original longitudinal alignment. Use the hand's width axis to distribute
    # roll through the forearm instead of concentrating twist at the wrist.
    hand_y = hand_matrix.to_3x3().col[1].normalized()
    forearm_reference = tool_rotation @ arm_references[side]['ForeArm']
    ideal = wrist-(forearm_reference @ Vector((0, 1, 0)))*lower-origin
    ideal = (ideal-axis*ideal.dot(axis)).normalized()
    pole = (ideal*.05+natural*.95).normalized()
    elbow = origin+axis*along+pole*math.sqrt(max(0, upper*upper-along*along))
    orient(side+'Arm', origin, elbow-origin, (source_rotation @ arm_references[side]['Arm']) @ Vector((1, 0, 0)))
    orient(side+'ForeArm', elbow, wrist-elbow, forearm_reference @ Vector((1, 0, 0)))
    rig.pose.bones[side+'Hand'].matrix = hand_matrix
    bpy.context.view_layer.update()
    return {'reach_fraction': distance/(upper+lower), 'wrist_error_m': (rig.pose.bones[side+'Hand'].head-wrist).length,
            'wrist_alignment': hand_y.dot((wrist-elbow).normalized())}


def smooth(t):
    return t*t*(3-2*t)


# Coordinates are Blender armature space: -X is the player's RIGHT, -Y forward,
# +Z up. The working point drives FORWARD toward the aim line, with a small
# leftward/downward diagonal. The follow-through remains in front of the player.
# Frame, handle pivot, rightward shaft lean (degrees), forward pitch, torso turn.
READY = ((-.04, -.55, 1.30), 38, .35, 0)
TIP = Vector((-.326, 0, .535))  # Center of the original mesh's sharpened point.


def tool_rotation(lean, pitch):
    return Quaternion((0, 1, 0), -math.radians(lean)) @ Quaternion((1, 0, 0), pitch) @ source_rotation


def aimed_pivot(target, lean, pitch):
    return tuple(Vector(target)-tool_rotation(lean, pitch) @ TIP)


# Hold the nearly accepted v4 contact orientation through the complete lateral
# crossover. Only the tool position changes during frames 26-46: no extra roll,
# yaw or torso rotation. Its original diagonal ready hold returns afterward.
KEYS = [(0, *READY),
        (12, ((-.10, -.44, 1.36)), 44, .22, -3),
        (20, ((-.14, -.35, 1.42)), 50, .20, -4),
        (26, ((-.31, -.34, 1.34)), -6, .60, 0),
        (32, ((-.08, -.49, 1.30)), -6, .60, 0),
        (42, ((.24, -.30, 1.22)), -6, .60, 0),
        (46, ((.23, -.29, 1.23)), -6, .60, 0),
        (57, ((.03, -.43, 1.26)), 17, .48, .5),
        (72, *READY)]


def swing_pose(frame):
    # Monotone cubic interpolation keeps the strike moving through contact,
    # rather than easing to a stop at every intermediate key pose.
    values = [[*key[1], *key[2:]] for key in KEYS]
    def tangent(index, component):
        if index == 0 or index == len(KEYS)-1:
            return 0.0
        before = (values[index][component]-values[index-1][component])/(KEYS[index][0]-KEYS[index-1][0])
        after = (values[index+1][component]-values[index][component])/(KEYS[index+1][0]-KEYS[index][0])
        return 2*before*after/(before+after) if before*after > 0 else 0.0
    for index, (a, b) in enumerate(zip(KEYS, KEYS[1:])):
        if a[0] <= frame <= b[0]:
            interval = b[0]-a[0]
            t = (frame-a[0])/interval
            h00, h10 = 2*t*t*t-3*t*t+1, t*t*t-2*t*t+t
            h01, h11 = -2*t*t*t+3*t*t, t*t*t-t*t
            result = [h00*values[index][component]+h10*interval*tangent(index, component)
                      +h01*values[index+1][component]+h11*interval*tangent(index+1, component)
                      for component in range(6)]
            return Vector(result[:3]), *result[3:]
    raise ValueError(frame)


records = {}
actions = {}
scene.render.fps = FPS
for motion, duration in durations.items():
    action = bpy.data.actions.new(PREFIX+motion)
    rig.animation_data_create()
    rig.animation_data.action = action
    records[motion] = []
    count = round(duration*FPS)
    for frame in range(count+1):
        scene.frame_set(frame)
        pose = lower_poses[motion][frame] if motion in lower_poses else base
        for bone in rig.pose.bones:
            bone.rotation_mode = 'QUATERNION'
            bone.matrix_basis = pose[bone.name]
        bpy.context.view_layer.update()
        if motion == 'Swing':
            pivot, lean, pitch, turn = swing_pose(frame)
            rig.pose.bones['Spine2'].rotation_quaternion @= Quaternion((0, 1, 0), math.radians(turn))
        else:
            phase = frame/count*math.tau
            amplitude = {'Idle': .002, 'Walk': .008, 'Run': .014, 'Jump': .008}[motion]
            pivot = Vector(READY[0])+Vector((amplitude*.4*math.sin(phase), 0, amplitude*math.sin(phase)))
            lean, pitch = READY[1:3]
        bpy.context.view_layer.update()
        rotation = tool_rotation(lean, pitch)
        tool = Matrix.LocRotScale(pivot, rotation, Vector((1, 1, 1)))
        rig.pose.bones['Weapon_Pickaxe'].matrix = tool @ rest_tool
        bpy.context.view_layer.update()
        reach = {side: arm(side, tool @ grips[side], rotation) for side in ['Left', 'Right']}
        for bone in rig.pose.bones:
            bone.keyframe_insert('location', frame=frame, group=bone.name)
            bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
            bone.keyframe_insert('scale', frame=frame, group=bone.name)
        head = tool @ Vector((0, 0, .60))
        records[motion].append({'frame': frame, 'head': list(head), 'working_tip': list(tool @ TIP), 'pivot': list(pivot), 'tool_quaternion_wxyz': list(rotation),
                                'left_wrist': list(rig.pose.bones['LeftHand'].head),
                                'right_wrist': list(rig.pose.bones['RightHand'].head), 'reach': reach})
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'
    action.use_fake_user = True
    # Explicit per-action ranges prevent the longer idle from extending a strike.
    action.use_frame_range = True
    action.frame_start, action.frame_end = 0, count
    actions[motion] = action

scene.frame_start, scene.frame_end = 0, 180
rig['pickaxe_description'] = 'SEPARATE REVIEW COPY: full right-to-left tool travel; v4 contact orientation held FIXED throughout crossover. No additional left twist or torso turn during frames 26-46. Recover to the same ready hold. Baseline v4 is preserved; do not commit.'
rig['pickaxe_strike_frames'] = '26 to 42 at 60 FPS; left follow-through to 46; recovery 46 to 72'
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        obj.hide_render = obj.name.startswith(('Equipment.', 'Hair.', 'Brows.', 'Eye')) and obj.name != 'Equipment.Pickaxe'

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
rig.animation_data.action = actions['Idle']
scene.frame_set(0)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT/'Human.pickaxe_full_sweep.glb'), export_format='GLB',
    use_selection=True, export_materials='NONE', export_animations=True,
    export_animation_mode='ACTIONS', export_frame_range=False, export_force_sampling=True,
    export_skins=True, export_morph=False, export_yup=True)

# A first-person editing camera matches the runtime's 75-degree vertical FOV.
data = bpy.data.cameras.new('Pickaxe First Person')
camera = bpy.data.objects.new('Pickaxe First Person', data)
scene.collection.objects.link(camera)
camera.location = (0, .03, 1.65)
camera.rotation_euler = (Vector((0, -1, 1.65))-camera.location).to_track_quat('-Z', 'Y').to_euler()
data.sensor_fit, data.sensor_height = 'VERTICAL', 24
data.lens = 24/(2*math.tan(math.radians(75)/2))
data.clip_start = .025
scene.camera = camera
scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
scene.render.resolution_percentage = 100
scene.world = bpy.data.worlds.new('Pickaxe Review Studio')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.075, .105, .14, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .4
for name, location, energy in [('Pickaxe Key', (-1.8, -1.6, 3), 200), ('Pickaxe Fill', (1.5, -.4, 2.4), 120)]:
    light_data = bpy.data.lights.new(name, 'AREA')
    light_data.energy, light_data.size = energy, 2
    light = bpy.data.objects.new(name, light_data)
    scene.collection.objects.link(light)
    light.location = location
    light.rotation_euler = (Vector((0, -.5, 1.4))-light.location).to_track_quat('-Z', 'Y').to_euler()
for material in bpy.data.materials:
    if ('Human.Head' in material.name or 'Human.Mouth' in material.name) and material.use_nodes:
        nodes = material.node_tree.nodes
        output = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None)
        if output and output.inputs['Surface'].is_linked:
            original = output.inputs['Surface'].links[0].from_socket
            transparent = nodes.new('ShaderNodeBsdfTransparent')
            ray = nodes.new('ShaderNodeLightPath')
            mix = nodes.new('ShaderNodeMixShader')
            material.node_tree.links.new(ray.outputs['Is Camera Ray'], mix.inputs[0])
            material.node_tree.links.new(original, mix.inputs[1])
            material.node_tree.links.new(transparent.outputs[0], mix.inputs[2])
            material.node_tree.links.new(mix.outputs[0], output.inputs['Surface'])
scene.render.engine = 'CYCLES'
scene.cycles.device, scene.cycles.samples = 'CPU', 32
scene.timeline_markers.clear()
rig.animation_data.action = actions['Swing']
scene.frame_end = 72
for label, frame in [('READY', 0), ('CHAMBER RIGHT', 20), ('CROSS CENTER', 32), ('FULL LEFT FOLLOW THROUGH', 42), ('RECOVER', 57), ('READY AGAIN', 72)]:
    scene.timeline_markers.new(label, frame=frame)
scene.frame_set(0)
report = {'approval': 'PENDING USER VISUAL REVIEW; do not commit', 'blender': bpy.app.version_string,
          'source': str(source.relative_to(ROOT)), 'source_sha256': source_hash, 'fps': FPS,
          'actions': {PREFIX+name: {'duration': duration, 'frames': [0, round(duration*FPS)]} for name, duration in durations.items()},
          'revision': 'Separate copy: complete right-to-left crossover with fixed tool orientation; reduced-twist v4 remains unchanged',
          'strike_frames': [26, 42], 'contact_frame': 32, 'fixed_orientation_frames': [26, 46],
          'working_tip_local': list(TIP),
          'coordinate_convention': '-X = player right; +X = player left; -Y forward; +Z up',
          'grip_source': 'R11 FP_Pickaxe_RightGrip_Idle, original fitted hand wraps',
          'samples': records}
(OUTPUT/'Human.pickaxe_full_sweep.json').write_text(json.dumps(report, indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT/'Human.pickaxe_full_sweep.blend'), compress=True)
print('PICKAXE_DIAGONAL_AUTHORED', json.dumps({k:v for k,v in report.items() if k!='samples'}))
