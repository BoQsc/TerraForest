# SPDX-License-Identifier: 0BSD
"""Run in Blender on Human.r11.blend to author the relaxed placement action."""
import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'addons/characters/authoring'
PREVIEW = ROOT / 'reports/human_placement/blender'
NAME = 'FP_Place_Relaxed'
OUTPUT.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)
(OUTPUT / '.gdignore').touch()
source = Path(bpy.data.filepath)
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
rig.animation_data.action = bpy.data.actions['Idle']
if rig.animation_data.action.slots:
    rig.animation_data.action_slot = rig.animation_data.action.slots[0]
scene.frame_set(1)
bpy.context.view_layer.update()
base = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type == 'MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)

def restore():
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.matrix_basis = base[bone.name]
    bpy.context.view_layer.update()

def orient(name, head, direction):
    bone = rig.pose.bones[name]
    rest = rig.data.bones[name].matrix_local.to_quaternion()
    rotation = (rest @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ rest
    bone.matrix = Matrix.LocRotScale(head, rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()

def gesture(dip=0.0):
    restore()
    clavicle = rig.pose.bones['RightShoulder'].head.copy()
    orient('RightShoulder', clavicle, Vector((-.12, -.08, .01)))
    shoulder = rig.pose.bones['RightArm'].head.copy()
    wrist = Vector((-.235, -.445 - dip * .012, 1.505 - dip * .008))
    upper = rig.data.bones['RightArm'].length
    lower = rig.data.bones['RightForeArm'].length
    direction = wrist - shoulder
    distance = direction.length
    axis = direction.normalized()
    along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
    pole = Vector((-.6, -.05, 1.72)) - shoulder
    pole = (pole - axis * pole.dot(axis)).normalized()
    elbow = shoulder + axis * along + pole * math.sqrt(max(0, upper * upper - along * along))
    orient('RightArm', shoulder, elbow - shoulder)
    orient('RightForeArm', elbow, wrist - elbow)
    # "Downwards" describes where the hand is held, not wrist flexion. Keep
    # the palm's long axis aligned with the forearm throughout the gesture.
    y = (wrist - elbow).normalized()
    x = Vector((-1, 0, 0))
    x = (x - y * x.dot(y)).normalized()
    z = x.cross(y).normalized()
    rotation = Matrix((x, y, z)).transposed().to_quaternion()
    rotation = Quaternion(y, math.radians(-18)) @ rotation
    rig.pose.bones['RightHand'].matrix = Matrix.LocRotScale(wrist, rotation, Vector((1, 1, 1)))
    # Index is soft, not locked straight. Other digits make a loose cascade;
    # the thumb keeps its original opposition and a small natural flexion.
    curls = {'Index': (-6 + dip * 3, -8 + dip * 2, -6),
             'Middle': (14, 28, 15), 'Ring': (19, 35, 20),
             'Pinky': (24, 40, 20), 'Thumb': (8, 11, 7)}
    for finger, angles in curls.items():
        for joint, degrees in enumerate(angles, 1):
            rig.pose.bones[f'RightHand{finger}{joint}'].rotation_quaternion = Quaternion((1, 0, 0), -math.radians(degrees))
    bpy.context.view_layer.update()
    return {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}

target = gesture()
contact = gesture(1.0)
action = bpy.data.actions.new(NAME)
rig.animation_data_create()
rig.animation_data.action = action
scene.render.fps = 30
scene.frame_start, scene.frame_end = 0, 27
keys = [(0, 0.0, False), (5, .82, False), (9, 1.0, False),
        (13, 1.0, True), (18, 1.0, False), (23, .55, False), (27, 0.0, False)]
for frame, weight, pressing in keys:
    scene.frame_set(frame)
    for bone in rig.pose.bones:
        pose = contact[bone.name] if pressing else target[bone.name]
        position, rotation, scale = base[bone.name].decompose()
        target_position, target_rotation, target_scale = pose.decompose()
        bone.location = position.lerp(target_position, weight)
        bone.rotation_quaternion = rotation.slerp(target_rotation, weight)
        bone.scale = scale.lerp(target_scale, weight)
        bone.keyframe_insert('location', frame=frame, group=bone.name)
        bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
        bone.keyframe_insert('scale', frame=frame, group=bone.name)
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:
                    key.interpolation = 'BEZIER'
                    key.handle_left_type = key.handle_right_type = 'AUTO_CLAMPED'
action.use_fake_user = True
rig['placement_action'] = NAME
rig['placement_description'] = 'Empty relaxed right hand held low; neutral wrist aligned with forearm, softly extended index, naturally opposed thumb. No root motion or gameplay event tracks.'
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        obj.hide_render = obj.name.startswith(('Equipment.', 'Hair.', 'Brows.', 'Eye'))

# Export only the original rig and its body, without materials. The body supplies
# the skin/joint map; Godot's conversion step retains only the AnimationLibrary.
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
scene.frame_set(0)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT / 'Human.placement.glb'), export_format='GLB',
    use_selection=True, export_materials='NONE', export_animations=True,
    export_animation_mode='ACTIONS', export_frame_range=True, export_force_sampling=True,
    export_skins=True, export_morph=False, export_yup=True)

def camera(name, location, target, lens=40):
    data = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    data.lens = lens
    data.clip_start = .025
    return obj

def area(name, location, power, size, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size, data.color = power, 'DISK', size, color
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((-.2, -.35, 1.35)) - obj.location).to_track_quat('-Z', 'Y').to_euler()

scene.world = bpy.data.worlds.new('Placement Studio')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.075, .105, .14, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .4
area('Placement Key', (-1.8, -1.6, 3), 170, 2.0, (1.0, .86, .73))
area('Placement Fill', (1.5, -.4, 2.4), 120, 1.8, (.73, .84, 1.0))
area('Placement Rim', (-.5, 1.5, 2.2), 180, 1.2, (1, 1, 1))
fp = camera('Placement First Person', (0, .03, 1.65), (0, -1, 1.65), 24)
fp.data.sensor_fit = 'VERTICAL'
fp.data.sensor_height = 24
fp.data.lens = 24 / (2 * math.tan(math.radians(75) / 2))
close = camera('Placement Hand Detail', (-.66, -1.05, 1.74), (-.23, -.54, 1.46), 65)
# Match the runtime's first-person head masking for the studio camera. This
# modifies only the derivative source's materials, never the preserved R11 file.
for material in bpy.data.materials:
    if ('Human.Head' in material.name or 'Human.Mouth' in material.name) and material.use_nodes:
        nodes = material.node_tree.nodes
        output = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None)
        if output and output.inputs['Surface'].is_linked:
            original = output.inputs['Surface'].links[0].from_socket
            transparent = nodes.new('ShaderNodeBsdfTransparent')
            light_path = nodes.new('ShaderNodeLightPath')
            mix = nodes.new('ShaderNodeMixShader')
            material.node_tree.links.new(light_path.outputs['Is Camera Ray'], mix.inputs[0])
            material.node_tree.links.new(original, mix.inputs[1])
            material.node_tree.links.new(transparent.outputs[0], mix.inputs[2])
            material.node_tree.links.new(mix.outputs[0], output.inputs['Surface'])
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 32
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.frame_set(13)
scene.camera = close
report = {'blender': bpy.app.version_string, 'source': str(source.relative_to(ROOT)),
          'source_sha256': source_hash, 'action': NAME, 'fps': 30, 'frames': [0, 27],
          'duration_seconds': .9, 'rig_bones': len(rig.data.bones), 'keyframes': [x[0] for x in keys],
          'contact_pose': {b.name: {'head': list(b.head), 'tail': list(b.tail)} for b in rig.pose.bones if b.name.startswith('RightHand')}}
(OUTPUT / 'Human.placement.json').write_text(json.dumps(report, indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / 'Human.placement.blend'), compress=True)
for label, cam in [('first_person', fp), ('hand_detail', close)]:
    scene.camera = cam
    scene.render.filepath = str(PREVIEW / (label + '.png'))
    bpy.ops.render.render(write_still=True)
print('HUMAN_PLACEMENT_AUTHORED', NAME, str(OUTPUT))
