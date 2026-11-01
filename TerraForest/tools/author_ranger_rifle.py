# SPDX-License-Identifier: 0BSD
"""Original CC0 Ranger assault-rifle meshes. Run Blender with --factory-startup.

Only original geometry and flat PBR materials are exported. Hand/magazine anchors
match the project's existing weapon rig; no character mesh or rig is copied.
"""
import hashlib
import json
import math
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'addons/characters/authoring'
ASSETS = ROOT / 'addons/characters/runtime/assets'
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
parts = []


def material(name, color, metal=0, rough=.5):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metal
    shader.inputs['Roughness'].default_value = rough
    return mat


olive = material('Ranger.Olive ceramic', (.20, .255, .13), .28, .57)
steel = material('Ranger.Graphite steel', (.075, .095, .102), .78, .32)
edge = material('Ranger.Machined edges', (.31, .36, .37), .85, .3)
rubber = material('Ranger.Grip rubber', (.025, .032, .029), 0, .88)
dark = material('Ranger.Recesses', (.012, .018, .02), .3, .7)
mark = material('Ranger.Sight paint', (.78, .85, .48), 0, .5)


def finish(obj, name, mat, bevel=0):
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new('Small machined edge', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        normal = obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
        bpy.ops.object.modifier_apply(modifier=normal.name)
    parts.append(obj)
    return obj


def box(name, center, size, mat, bevel=.002, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.dimensions = size
    obj.rotation_euler.x = angle
    return finish(obj, name, mat, bevel)


def tube(name, center, radius, length, mat, axis='Y'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=length, location=center)
    obj = bpy.context.object
    obj.rotation_euler.x = math.pi/2 if axis == 'Y' else 0
    if axis == 'X': obj.rotation_euler.y = math.pi/2
    return finish(obj, name, mat, .0008)


box('Upper receiver', (0, -.088, .118), (.061, .268, .078), olive, .007)
box('Receiver seam', (0, -.075, .077), (.055, .224, .008), steel, .001)
box('Lower receiver', (0, -.063, .061), (.051, .173, .03), olive, .004)
box('Pistol grip', (0, .004, -.012), (.038, .048, .118), rubber, .009, -.16)
for z in [-.053, -.034, -.015, .004]:
    box('Grip moulding', (0, .027, z), (.039, .007, .004), steel, .001)
box('Trigger guard front', (0, -.069, .025), (.012, .009, .049), steel, .003)
box('Trigger guard bottom', (0, -.04, .003), (.012, .066, .008), steel, .003)
box('Trigger', (0, -.036, .043), (.007, .008, .034), edge, .002, -.24)
box('Handguard', (0, -.29, .115), (.052, .179, .061), olive, .006)
box('Handguard palm', (0, -.277, .083), (.045, .165, .011), rubber, .003)
for side in [-1, 1]:
    for y in [-.227, -.257, -.287, -.317, -.347]:
        box('Vent recess', (side*.0265, y, .124), (.003, .018, .014), dark, .002)
    box('Receiver bevel plate', (side*.0308, -.105, .113), (.003, .127, .031), steel, .002)
    for y in [-.018, -.19]:
        tube('Receiver pin', (side*.032, y, .105), .0045, .003, edge, 'X')
box('Ejection port', (.032, -.087, .14), (.003, .065, .016), dark, .002)
box('Bolt in port', (.034, -.077, .139), (.002, .033, .009), edge, .001)
box('Charging handle', (-.039, -.047, .15), (.023, .015, .009), steel, .002)
box('Selector', (-.033, .006, .079), (.005, .022, .008), edge, .001, -.4)
tube('Barrel', (0, -.466, .127), .012, .178, steel)
tube('Gas block', (0, -.383, .127), .020, .025, steel)
tube('Muzzle collar', (0, -.56, .127), .019, .042, edge)
tube('Muzzle crown', (0, -.583, .127), .017, .007, steel)
tube('Muzzle dark bore', (0, -.587, .127), .009, .001, dark)
for side in [-1, 1]:
    for y in [-.552, -.567]:
        box('Muzzle vent', (side*.017, y, .127), (.003, .008, .014), dark, .001)
box('Top rail base', (0, -.157, .162), (.033, .417, .009), steel, .001)
for i in range(28):
    box('Rail tooth', (0, .038-i*.0145, .17), (.039, .007, .007), steel, .0008)
box('Rear sight bridge', (0, .016, .178), (.038, .025, .013), steel, .002)
for x in [-.014, .014]:
    box('Rear sight ear', (x, .017, .192), (.007, .019, .023), steel, .001)
    box('Rear sight paint', (x, .027, .197), (.003, .001, .004), mark, .0003)
box('Front sight base', (0, -.36, .173), (.032, .023, .016), steel, .002)
for x in [-.014, .014]:
    box('Front sight guard', (x, -.36, .191), (.005, .015, .027), steel, .001)
box('Front sight post', (0, -.36, .191), (.004, .007, .026), edge, .0008)
box('Front sight paint', (0, -.3555, .2), (.003, .001, .005), mark, .0003)
tube('Stock extension', (0, .126, .122), .018, .175, steel)
box('Stock cheek pad', (0, .199, .15), (.048, .148, .035), olive, .005)
box('Stock lower strut', (0, .19, .068), (.025, .215, .025), olive, .004, -.32)
box('Stock heel', (0, .292, .113), (.046, .028, .132), olive, .006)
box('Butt pad', (0, .313, .114), (.051, .016, .139), rubber, .005)
for z in [.065, .085, .105, .125, .145, .165]:
    box('Butt pad ribs', (0, .322, z), (.044, .005, .004), steel, .001)
body_parts = parts.copy()
parts.clear()
# The insertion anchor and grasp band stay aligned with Weapon_Magazine.
box('Magazine neck', (0, -.122, .02), (.035, .058, .10), steel, .003)
box('Magazine upper', (0, -.125, -.044), (.038, .064, .062), olive, .004, -.08)
box('Magazine lower', (0, -.138, -.104), (.038, .067, .07), olive, .004, -.26)
box('Magazine foot', (0, -.149, -.14), (.043, .074, .014), rubber, .003, -.26)
for side in [-1, 1]:
    for y in [-.145, -.126, -.107]:
        box('Magazine upper rib', (side*.020, y, -.043), (.003, .005, .049), steel, .001, -.08)
        box('Magazine lower rib', (side*.020, y-.013, -.104), (.003, .005, .052), steel, .001, -.26)
mag_parts = parts.copy()


def join(group, name):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in group: obj.select_set(True)
    bpy.context.view_layer.objects.active = group[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj['license'] = 'CC0-1.0'
    obj['creator'] = 'OpenAI Codex / TerraForest contributors'
    return obj


body = join(body_parts, 'Equipment_Ranger_Body')
mag = join(mag_parts, 'Equipment_Ranger_Magazine')
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Ranger.blend'))
outputs = {}
for obj, suffix in [(body, 'body'), (mag, 'magazine')]:
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = ASSETS/f'Ranger.{suffix}.glb'
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                              export_animations=False, export_extras=True)
    outputs[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
(OUT/'Ranger.json').write_text(json.dumps(dict(license='CC0-1.0', creator='OpenAI Codex',
    tool='Blender '+bpy.app.version_string, source='Original geometry authored in tools/author_ranger_rifle.py',
    reference='Existing Human.r11 weapon grip/magazine anchors only; no mesh, rig, texture or animation copied into these assets.',
    outputs=outputs), indent=2)+'\n')
print('RANGER_AUTHOR complete', outputs)
