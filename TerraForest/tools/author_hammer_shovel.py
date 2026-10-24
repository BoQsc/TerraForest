# SPDX-License-Identifier: 0BSD
"""Blender R11 authoring: --python tools/author_hammer_shovel.py -- hammer|shovel.

Run against the preserved Human.r11.blend. Saves separate editable sources,
animation-only GLBs and rigid tool GLBs without changing the original delivery.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'addons/characters/authoring'
ASSETS = ROOT / 'addons/characters/runtime/assets'
KIND = sys.argv[sys.argv.index('--') + 1]
assert KIND in ('hammer', 'shovel')
source = Path(bpy.data.filepath)
assert source.name == 'Human.r11.blend'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
rig = bpy.data.objects['Human_Rig']
scene = bpy.context.scene
FPS = 60
TITLE = KIND.capitalize()
PREFIX = f'FP_{TITLE}_'
BONE = 'Weapon_Axe' if KIND == 'hammer' else 'Weapon_Pickaxe'
SOURCE = 'FP_Axe_' if KIND == 'hammer' else 'FP_Pickaxe_RightGrip_'
END = 60 if KIND == 'hammer' else 84
CONTACT = 28 if KIND == 'hammer' else 34
DURATIONS = {'Idle': 3.0, 'Walk': 1.0, 'Run': .8, 'Jump': 1.5, 'Swing': END/FPS}
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)


def sample(action, frame):
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(int(frame), subframe=frame-int(frame))
    bpy.context.view_layer.update()
    return {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}


base = sample(bpy.data.actions[SOURCE+'Idle'], 1.0)
source_tool = rig.pose.bones[BONE].matrix.copy()
source_rotation = source_tool.to_quaternion()
sides = ['Right'] if KIND == 'hammer' else ['Left', 'Right']
grips = {side: source_tool.inverted() @ rig.pose.bones[side+'Hand'].matrix for side in sides}
references = {side: {part: rig.pose.bones[side+part].matrix.copy()
                     for part in ['Arm', 'ForeArm']} for side in sides}
lower = {}
for motion in ['Walk', 'Run', 'Jump']:
    action = bpy.data.actions[SOURCE+motion]
    start, end = action.frame_range
    count = round(DURATIONS[motion]*FPS)
    lower[motion] = [sample(action, start+(end-start)*i/count) for i in range(count+1)]

for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type == 'MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            if key.name != 'Basis':
                key.value = 0
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)


def material(name, color, metallic=0, roughness=.65):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return mat


wood = material('Tools.Oiled ash', (.30, .145, .058), 0, .73)
steel = material('Tools.Forged steel', (.21, .26, .29), .72, .40)
edge = material('Tools.Polished working edge', (.49, .55, .57), .85, .29)
dark = material('Tools.Dark collar', (.07, .085, .09), .6, .52)
parts = []


def steel_maps(mat, polished=False):
    """Embedded PBR maps: subtle brushed steel, uneven roughness, micro scratches."""
    size = 1024
    rng = np.random.default_rng(592 if polished else 351)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)/size
    grain = rng.normal(0, 1, (size, size)).astype(np.float32)
    bands = (np.sin(x*173+y*13)*.35+np.sin(x*591-y*29)*.16
             +np.sin(x*45+y*73)*np.sin(y*27)*.32)
    brushed = np.sin(x*size*2.4+np.sin(y*19)*.8)*.35+grain*.20
    scratches = np.zeros((size, size), dtype=np.float32)
    for _ in range(240):
        column = rng.integers(1, size-2)
        start = rng.integers(0, size-60)
        length = rng.integers(12, 180)
        scratches[start:min(size,start+length), column:column+1] += rng.uniform(.15,.6)
    value = np.clip(.53+bands*.025+brushed*.012+scratches*.025, 0, 1)
    tint = np.array([.90, .95, 1.0], dtype=np.float32)
    base = value[...,None]*tint
    if polished:
        base = np.clip(base+.16, 0, 1)
    roughness = np.clip((.26 if polished else .42)+bands*.038+grain*.018-scratches*.10, .18, .60)
    height = brushed*.00020+scratches*.00030+bands*.00010
    dy, dx = np.gradient(height)
    normals = np.stack((-dx*1000, -dy*1000, np.ones_like(dx)), axis=-1)
    normals /= np.linalg.norm(normals, axis=-1, keepdims=True)
    normals = normals*.5+.5
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get('Principled BSDF')
    for label, pixels, color_space in [('BaseColor', base, 'sRGB'),
            ('Roughness', np.repeat(roughness[...,None],3,axis=-1), 'Non-Color'),
            ('Normal', normals, 'Non-Color')]:
        data = bpy.data.images.new(mat.name+'.'+label, width=size, height=size, alpha=False)
        data.colorspace_settings.name = color_space
        rgba = np.ones((size,size,4), dtype=np.float32)
        rgba[:,:,:3] = pixels
        data.pixels.foreach_set(rgba.ravel())
        data.update()
        data.pack()
        texture = nodes.new('ShaderNodeTexImage')
        texture.image = data
        texture.label = label
        if label == 'Normal':
            normal = nodes.new('ShaderNodeNormalMap')
            normal.inputs['Strength'].default_value = .32
            links.new(texture.outputs['Color'], normal.inputs['Color'])
            links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
        else:
            links.new(texture.outputs['Color'], bsdf.inputs['Base Color' if label=='BaseColor' else 'Roughness'])
    bsdf.inputs['Metallic'].default_value = .96


steel_maps(steel)
steel_maps(edge, polished=True)


def finish(obj, mat, bevel=0):
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new('Forged edge bevel', 'BEVEL')
        modifier.width, modifier.segments = bevel, 5
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    parts.append(obj)
    return obj


def box(name, at, size, mat, bevel=.006):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.name, obj.scale = name, size
    return finish(obj, mat, bevel)


def shaft(name, a, b, radius, mat, radius_top=None):
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=radius,
        radius2=radius if radius_top is None else radius_top, depth=(b-a).length,
        location=(a+b)*.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = (b-a).to_track_quat('Z', 'Y')
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(obj, mat, .0015)


if KIND == 'hammer':
    shaft('Ash handle', (0, 0, -.13), (0, 0, .365), .021, wood, .018)
    shaft('Handle heel', (0, 0, -.145), (0, 0, -.115), .024, dark)
    shaft('Head socket', (0, 0, .30), (0, 0, .39), .027, dark)
    # One continuous head, two flush flat faces: no player-facing peen/bump.
    rings, around = 49, 96
    vertices, faces = [], []
    for i in range(rings):
        along = -.162+.324*i/(rings-1)
        chamfer = math.exp(-((abs(along)-.162)/.008)**2)
        radius = .055-.008*chamfer-.0015*(1-(along/.162)**2)
        for j in range(around):
            angle = math.tau*j/around
            c, s = math.cos(angle), math.sin(angle)
            yy = math.copysign(abs(c)**.34, c)*radius
            zz = math.copysign(abs(s)**.34, s)*radius
            vertices.append((along, yy, .39+zz))
    for i in range(rings-1):
        for j in range(around):
            a = i*around+j; b = i*around+(j+1)%around
            faces.append((a,b,b+around,a+around))
    faces.extend([tuple(reversed(range(around))), tuple((rings-1)*around+j for j in range(around))])
    data = bpy.data.meshes.new('Dense forged hammer head')
    data.from_pydata(vertices, [], faces);data.update()
    head = bpy.data.objects.new('Flush-faced forged hammer head',data);scene.collection.objects.link(head)
    data.materials.append(steel);data.materials.append(edge)
    for polygon in data.polygons:
        polygon.use_smooth = polygon.index < (rings-1)*around
        polygon.material_index = 1 if polygon.index >= (rings-1)*around or polygon.index<around or polygon.index >= (rings-2)*around else 0
    parts.append(head)
    TIP = Vector((-.162, 0, .39))
    READY = ((-.22, -.47, 1.37), 15, .25)
    KEYS = [(0, *READY), (12, (-.25, -.39, 1.35), 24, -.12),
            (20, (-.25, -.32, 1.43), 28, -.35),
            (28, (-.14, -.55, 1.29), -4, 1.00),
            (33, (-.13, -.56, 1.25), -6, 1.12),
            (40, (-.17, -.53, 1.26), 3, .85), (60, *READY)]
else:
    shaft('Ash shaft', (0, 0, -.27), (0, 0, .49), .020, wood, .018)
    shaft('Steel socket', (0, 0, .35), (0, 0, .51), .026, steel, .022)
    # D grip sits at the heel, opposite the blade. It is open geometry.
    for sign in [-1, 1]:
        shaft('D grip side', (sign*.027, 0, -.26), (sign*.078, 0, -.39), .012, dark)
    shaft('D grip crossbar', (-.078, 0, -.39), (.078, 0, -.39), .018, wood)
    # Shallow dished blade with shoulders and a rounded-point cutting end.
    rows, columns = 57, 65
    vertices = []
    for row in range(rows):
        t = row/(rows-1)
        z = .44+.33*t
        width = .09+.05*math.sin(t/.18*math.pi/2) if t<.18 else .14*math.sqrt(max(.00005,1-((t-.18)/.82)**2))
        for column in range(columns):
            factor = -1+2*column/(columns-1)
            # The player sees the concave inside (+Y); the cutting end still
            # leads forward because of the separate blade/shaft angle below.
            depth = -(.017+.020*math.sin(math.pi*t))*(1-factor*factor)
            depth += .004*math.exp(-(factor/.22)**2)*math.sin(math.pi*t)
            vertices.append((factor*width, depth, z))
    faces = []
    for row in range(rows-1):
        for column in range(columns-1):
            a = row*columns+column
            faces.append((a, a+1, a+columns+1, a+columns))
    data = bpy.data.meshes.new('Dished shovel blade')
    data.from_pydata(vertices, [], faces)
    data.update()
    blade = bpy.data.objects.new('Dished steel blade', data)
    scene.collection.objects.link(blade)
    bpy.context.view_layer.objects.active = blade
    blade.select_set(True)
    data.materials.append(steel)
    data.materials.append(edge)
    for polygon in data.polygons:
        polygon.use_smooth = True
        polygon.material_index = 1 if polygon.center.z > .735 else 0
    solid = blade.modifiers.new('Blade thickness', 'SOLIDIFY')
    solid.thickness = .004
    bpy.ops.object.modifier_apply(modifier=solid.name)
    parts.append(blade)
    back_socket = shaft('Raised back socket', (0,-.041,.45), (0,-.043,.61), .014, steel, .006)
    # The blade leads the shaft by twenty-five degrees, toward the dig rather
    # than toward the eye. Bend the blade/socket, leaving both fitted grips.
    blade_pivot = Vector((0,0,.44))
    blade_bend = Matrix.Rotation(math.radians(25),4,'X')
    for obj in [blade,back_socket]:
        transform = Matrix.Translation(blade_pivot) @ blade_bend @ Matrix.Translation(-blade_pivot)
        obj.matrix_world = transform @ obj.matrix_world
    TIP = Matrix.Rotation(-math.pi/2,4,'Z') @ (blade_pivot+blade_bend.to_3x3() @ Vector((0,0,.33)))
    READY = ((-.04, -.46, 1.30), 28, .75)
    KEYS = [(0, *READY), (14, (-.10, -.36, 1.34), 34, .53),
            (23, (-.14, -.34, 1.37), 29, .60),
            (34, (-.04, -.32, 1.27), 4, 1.65),
            (41, (-.03, -.34, 1.24), 2, 1.76),
            (53, (-.05, -.34, 1.25), 7, 1.24),
            (65, (-.06, -.42, 1.31), 20, .80), (84, *READY)]
    # The axe's local X is its working direction. A shovel instead needs the
    # blade width across the player, with the bowl facing the digging motion.
    for obj in parts:
        obj.matrix_world = Matrix.Rotation(-math.pi/2, 4, 'Z') @ obj.matrix_world

bpy.ops.object.select_all(action='DESELECT')
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
equipment = bpy.context.object
equipment.name = f'Equipment.{TITLE}'
scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# UVs cover every new dense surface; maps stay embedded in the GLB and .blend.
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(island_margin=.015)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.export_scene.gltf(filepath=str(ASSETS/f'{TITLE}.glb'), export_format='GLB',
    use_selection=True, export_animations=False, export_yup=True)
group = equipment.vertex_groups.new(name=BONE)
group.add(list(range(len(equipment.data.vertices))), 1.0, 'REPLACE')
modifier = equipment.modifiers.new('R11 rigid equipment', 'ARMATURE')
modifier.object = rig
equipment.parent = rig


def orient(name, position, direction, reference):
    q = reference.to_quaternion()
    q = (q @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ q
    rig.pose.bones[name].matrix = Matrix.LocRotScale(position, q, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def solve(side, target):
    origin = rig.pose.bones[side+'Arm'].head.copy()
    wrist = target.translation
    upper, fore = (rig.data.bones[side+part].length for part in ['Arm', 'ForeArm'])
    delta = wrist-origin
    distance = delta.length
    assert abs(upper-fore)+.001 < distance < upper+fore-.001, (KIND, side, scene.frame_current, distance, upper+fore)
    axis = delta.normalized()
    along = (upper*upper-fore*fore+distance*distance)/(2*distance)
    natural = Vector((.48 if side == 'Left' else -.48, -.10, 1.13))-origin
    pole = (natural-axis*natural.dot(axis)).normalized()
    elbow = origin+axis*along+pole*math.sqrt(max(0, upper*upper-along*along))
    orient(side+'Arm', origin, elbow-origin, references[side]['Arm'])
    orient(side+'ForeArm', elbow, wrist-elbow, references[side]['ForeArm'])
    rig.pose.bones[side+'Hand'].matrix = target
    bpy.context.view_layer.update()
    return {'reach_fraction': distance/(upper+fore),
            'wrist_error_m': (rig.pose.bones[side+'Hand'].head-wrist).length}


def swing_pose(frame):
    # Cubic Hermite interpolation with monotone tangents: no pause at contact.
    values = [[*key[1], *key[2:]] for key in KEYS]
    def tangent(i, c):
        if i in (0, len(KEYS)-1):
            return 0
        before = (values[i][c]-values[i-1][c])/(KEYS[i][0]-KEYS[i-1][0])
        after = (values[i+1][c]-values[i][c])/(KEYS[i+1][0]-KEYS[i][0])
        return 2*before*after/(before+after) if before*after > 0 else 0
    for i, (a, b) in enumerate(zip(KEYS, KEYS[1:])):
        if a[0] <= frame <= b[0]:
            width = b[0]-a[0]
            t = (frame-a[0])/width
            result = [(2*t**3-3*t*t+1)*values[i][c]+(t**3-2*t*t+t)*width*tangent(i,c)
                      +(-2*t**3+3*t*t)*values[i+1][c]+(t**3-t*t)*width*tangent(i+1,c) for c in range(5)]
            return Vector(result[:3]), *result[3:]
    raise ValueError(frame)


records, actions = {}, {}
scene.render.fps = FPS
for motion, duration in DURATIONS.items():
    action = bpy.data.actions.new(PREFIX+motion)
    rig.animation_data_create()
    rig.animation_data.action = action
    count = round(duration*FPS)
    records[motion] = []
    for frame in range(count+1):
        scene.frame_set(frame)
        pose = lower[motion][frame] if motion in lower else base
        for bone in rig.pose.bones:
            bone.rotation_mode = 'QUATERNION'
            bone.matrix_basis = pose[bone.name]
        bpy.context.view_layer.update()
        if motion == 'Swing':
            pivot, lean, pitch = swing_pose(frame)
        else:
            phase = frame/count*math.tau
            amplitude = {'Idle': .002, 'Walk': .006, 'Run': .010, 'Jump': .006}[motion]
            pivot = Vector(READY[0])+Vector((amplitude*.3*math.sin(phase), 0, amplitude*math.sin(phase)))
            lean, pitch = READY[1:]
        rotation = Quaternion((0, 1, 0), -math.radians(lean)) @ Quaternion((1, 0, 0), pitch) @ source_rotation
        tool = Matrix.LocRotScale(pivot, rotation, Vector((1, 1, 1)))
        rig.pose.bones[BONE].matrix = tool
        bpy.context.view_layer.update()
        reach = {side: solve(side, tool @ grips[side]) for side in sides}
        for bone in rig.pose.bones:
            bone.keyframe_insert('location', frame=frame, group=bone.name)
            bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
            bone.keyframe_insert('scale', frame=frame, group=bone.name)
        records[motion].append({'frame': frame, 'working_tip': list(tool @ TIP), 'reach': reach})
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'
    action.use_fake_user = True
    action.use_frame_range = True
    action.frame_start, action.frame_end = 0, count
    actions[motion] = action

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.data.objects['Human_Body'].select_set(True)
bpy.context.view_layer.objects.active = rig
rig.animation_data.action = actions['Idle']
scene.frame_set(0)
bpy.ops.export_scene.gltf(filepath=str(OUT/f'Human.{KIND}.glb'), export_format='GLB',
    use_selection=True, export_materials='NONE', export_animations=True,
    export_animation_mode='ACTIONS', export_frame_range=False, export_force_sampling=True,
    export_skins=True, export_morph=False, export_yup=True)

for obj in bpy.data.objects:
    if obj.type == 'MESH' and obj.name.startswith(('Equipment.', 'Hair.', 'Brows.', 'Eye')):
        obj.hide_render = obj != equipment
        obj.hide_set(obj != equipment)
camera_data = bpy.data.cameras.new(TITLE+' First Person')
camera = bpy.data.objects.new(TITLE+' First Person', camera_data)
scene.collection.objects.link(camera)
camera.location = (0, .03, 1.65)
camera.rotation_euler = Vector((0, -1, 0)).to_track_quat('-Z', 'Y').to_euler()
camera_data.sensor_fit, camera_data.sensor_height = 'VERTICAL', 24
camera_data.lens = 24/(2*math.tan(math.radians(75)/2))
camera_data.clip_start = .025
scene.camera = camera
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.render.resolution_percentage = 100
scene.timeline_markers.clear()
for label, frame in [('READY', 0), ('WINDUP', 20 if KIND == 'hammer' else 23),
                     ('CONTACT', CONTACT), ('FOLLOW THROUGH', 33 if KIND == 'hammer' else 41), ('READY AGAIN', END)]:
    scene.timeline_markers.new(label, frame=frame)
rig.animation_data.action = actions['Swing']
scene.frame_start, scene.frame_end = 0, END
scene.frame_set(0)
rig['tool_description'] = 'One-handed repair hammer' if KIND == 'hammer' else 'Two-handed shovel: thrust, lever, lift, recovery'
rig['contact_frame'] = CONTACT
rig['tool_bone'] = BONE
report = {'blender': bpy.app.version_string, 'source': str(source.relative_to(ROOT)),
          'source_sha256': source_hash, 'fps': FPS, 'tool_bone': BONE,
          'grip_source': SOURCE+'Idle', 'contact_frame': CONTACT,
          'working_tip_local': list(TIP),
          'equipment_vertices': len(equipment.data.vertices),
          'equipment_triangles': sum(len(p.vertices)-2 for p in equipment.data.polygons),
          'head_revision': 'Dense flush hammer faces; shovel cutting end leads shaft 25 degrees while concave inside faces eye; embedded 1024px brushed-steel PBR maps',
          'actions': {PREFIX+name: duration for name, duration in DURATIONS.items()},
          'max_reach_fraction': max(v['reach_fraction'] for samples in records.values() for row in samples for v in row['reach'].values()),
          'max_wrist_error_m': max(v['wrist_error_m'] for samples in records.values() for row in samples for v in row['reach'].values()),
          'samples': records}
if KIND == 'shovel':
    # Verify the actual ready-view face, not a label or an object Euler angle.
    opening = Matrix.Rotation(-math.pi/2,4,'Z').to_3x3() @ blade_bend.to_3x3() @ Vector((0,1,0))
    center = Matrix.Rotation(-math.pi/2,4,'Z') @ (blade_pivot+blade_bend.to_3x3() @ Vector((0,-.03,.16)))
    tool = rig.pose.bones[BONE].matrix
    toward_eye = (Vector((0,.03,1.65))-tool @ center).normalized()
    report['scoop_opening_dot_toward_eye'] = (tool.to_3x3() @ opening).normalized().dot(toward_eye)
    assert report['scoop_opening_dot_toward_eye'] > .3, report['scoop_opening_dot_toward_eye']
(OUT/f'Human.{KIND}.json').write_text(json.dumps(report, indent=2)+'\n')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'Human.{KIND}.blend'), compress=True)
print('TOOL_AUTHORED', json.dumps({k:v for k,v in report.items() if k != 'samples'}))
