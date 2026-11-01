# SPDX-License-Identifier: 0BSD
"""Author original grounded sleeper poses and wake trajectories on the retained R4 rig."""
import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "addons/characters/authoring"
SOURCE = Path(bpy.data.filepath)
assert SOURCE.name == "Zombie.r4.blend"
rig = bpy.data.objects["Zombie_Rig"]
scene = bpy.context.scene
rest = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones}
lengths = {bone.name: bone.length for bone in rig.data.bones}
for track in rig.animation_data.nla_tracks:
    track.mute = True


def original_pose(name):
    action = bpy.data.actions[name]
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(0)
    bpy.context.view_layer.update()
    return {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}


idle = original_pose("Zombie_Idle")
idle_global = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
crawl = original_pose("Zombie_Crawl_Idle")
soles = {}
for prefix, side in [("Left", "L"), ("Right", "R")]:
    mesh = bpy.data.objects["Z_Foot_" + side]
    vertices = [mesh.matrix_world @ vertex.co for vertex in mesh.data.vertices]
    bottom = min(point.z for point in vertices)
    soles[prefix] = [point for point in vertices if point.z < bottom + .025]
for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type == "MESH" and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:
            key.value = 0
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)
for bone in rig.pose.bones:
    bone.rotation_mode = "QUATERNION"


def oriented_frame(direction, normal):
    along = direction.normalized()
    across = along.cross(normal).normalized()
    perpendicular = across.cross(along).normalized()
    return Matrix((across, along, perpendicular)).transposed()


joint_frames = {}
for prefix in ["Left", "Right"]:
    for upper, lower in [(prefix + "UpLeg", prefix + "Leg"), (prefix + "Arm", prefix + "ForeArm")]:
        normal = rest[upper].to_3x3().col[1].cross(rest[lower].to_3x3().col[1]).normalized()
        for name in [upper, lower]:
            joint_frames[name] = oriented_frame(rest[name].to_3x3().col[1], normal).transposed() @ rest[name].to_3x3()


def solve_chain(upper, lower, target, pole):
    origin = rig.pose.bones[upper].head.copy()
    ray = target - origin
    distance = max(.025, min(ray.length, lengths[upper] + lengths[lower] - .008))
    direction = ray.normalized()
    actual = origin + direction * distance
    bend = pole - origin
    bend = (bend - direction * bend.dot(direction)).normalized()
    along = (lengths[upper] ** 2 - lengths[lower] ** 2 + distance ** 2) / (2 * distance)
    middle = origin + direction * along + bend * math.sqrt(max(.000001, lengths[upper] ** 2 - along ** 2))
    normal = (middle - origin).cross(actual - middle).normalized()
    for name, start, end in [(upper, origin, middle), (lower, middle, actual)]:
        matrix = (oriented_frame(end - start, normal) @ joint_frames[name]).to_4x4()
        matrix.translation = start
        rig.pose.bones[name].matrix = matrix
        bpy.context.view_layer.update()
    return actual, (actual - target).length


def local_rotation(name, pitch=0, yaw=0, roll=0):
    bone = rig.pose.bones[name]
    for axis, angle in [((1, 0, 0), pitch), ((0, 1, 0), yaw), ((0, 0, 1), roll)]:
        bone.rotation_quaternion = bone.rotation_quaternion @ Quaternion(axis, math.radians(angle))


def foot(prefix, forward, pitch, lift, lateral):
    rotation = Quaternion((1, 0, 0), math.radians(pitch))
    ankle = rest[prefix + "Foot"].translation
    points = [rotation @ (point - ankle) for point in soles[prefix]]
    target = Vector((ankle.x + lateral, forward, .003 + lift - min(point.z for point in points)))
    side = 1 if prefix == "Left" else -1
    target, error = solve_chain(prefix + "UpLeg", prefix + "Leg", target, Vector((side * .4, -.45, .6)))
    matrix = (rotation.to_matrix() @ rest[prefix + "Foot"].to_3x3()).to_4x4()
    matrix.translation = target
    rig.pose.bones[prefix + "Foot"].matrix = matrix
    bpy.context.view_layer.update()
    return error


def hand(prefix, target, floor_weight):
    side = 1 if prefix == "Left" else -1
    target, error = solve_chain(prefix + "Arm", prefix + "ForeArm", Vector(target), Vector((side * .7, .05, .5)))
    matrix = rig.pose.bones[prefix + "Hand"].matrix.copy()
    if floor_weight > 0:
        current = matrix.to_quaternion()
        direction = Vector((0, -1, -.12)).normalized()
        desired = (rest[prefix + "Hand"].to_3x3().col[1].rotation_difference(direction).to_matrix() @ rest[prefix + "Hand"].to_3x3()).to_quaternion()
        matrix = current.slerp(desired, floor_weight).to_matrix().to_4x4()
    matrix.translation = target
    rig.pose.bones[prefix + "Hand"].matrix = matrix
    bpy.context.view_layer.update()
    return error


def sample(time, poses):
    for (start, first), (end, second) in zip(poses, poses[1:]):
        if start <= time <= end:
            amount = (time - start) / (end - start)
            amount = amount * amount * (3 - 2 * amount)
            return [left + (right - left) * amount for left, right in zip(first, second)]
    return poses[-1][1]


SEATED = [0, 0, .16, 18, -3, 14, 22, -.70, 0, 0, -.56, 0, 0, .20, -.48, .29, -.20, -.43, .35, 0, 0]
LYING = [0, .03, .232, 87, 48, 2, 4, .72, 78, 0, .58, 62, 0, .35, -.38, .10, -.29, -.48, .12, 1, 1]
STAND = [0, 0, 1.0, 0, 0, 0, 0, .06, 0, 0, .06, 0, 0, .30, -.22, 1.10, -.30, -.22, 1.10, 0, 0]
SEATED_WAKE = [
    (0, SEATED),
    (.12, [0, 0, .17, 18, -3, 9, 7, -.70, 0, 0, -.56, 0, 0, .20, -.48, .29, -.20, -.43, .35, 0, 0]),
    (.30, [.02, -.08, .25, 48, -5, 6, -5, -.64, 5, .01, -.48, 0, 0, .31, -.40, .11, -.23, -.40, .40, 1, 0]),
    (.47, [.02, -.08, .44, 48, -4, 5, -6, -.28, 12, .06, -.20, 0, .035, .31, -.40, .29, -.23, -.36, .47, 0, 0]),
    (.64, [.01, -.03, .63, 30, 3, 5, -5, -.06, 0, 0, .06, 0, 0, .29, -.32, .56, -.24, -.30, .57, 0, 0]),
    (.83, [0, 0, .91, 8, -2, 3, 3, .06, 0, 0, .06, 0, 0, .30, -.26, .96, -.28, -.26, .96, 0, 0]),
    (1, STAND),
]
LYING_WAKE = [
    (0, LYING),
    (.14, [0, .03, .24, 83, 42, 0, -12, .72, 78, 0, .58, 62, 0, .35, -.38, .10, -.29, -.48, .12, 1, 1]),
    (.32, [0, .09, .37, 70, 16, 0, -10, .68, 72, 0, .42, 40, .03, .30, -.43, .11, -.27, -.42, .11, 1, 1]),
    (.49, [0, .03, .50, 44, 0, 2, -7, .43, 55, .01, -.12, 0, .03, .29, -.39, .34, -.26, -.36, .38, 0, 0]),
    (.67, [.01, .02, .67, 24, -4, 3, -4, .16, 15, .04, -.08, 0, 0, .26, -.29, .61, -.25, -.30, .66, 0, 0]),
    (.84, [0, 0, .93, 6, 1, 2, 2, .06, 0, 0, .06, 0, 0, .30, -.26, 1.0, -.28, -.26, 1.0, 0, 0]),
    (1, STAND),
]
SEATED_CRAWL = [
    (0, SEATED + [.015, -.015]),
    (.12, SEATED_WAKE[1][1] + [.015, -.015]),
    (.30, [0, -.02, .21, 55, -18, 5, -8, -.65, 5, .02, -.45, 15, .02, .20, -.70, .11, -.20, -.65, .13, 1, 1, .24, -.24]),
    (.50, [0, 0, .32, 75, -10, 3, -8, -.12, 30, .07, .20, 55, .03, .34, -.56, .11, -.32, -.53, .11, 1, 1, .40, -.32]),
    (.74, [0, 0, .27, 86, 0, 2, -8, .55, 70, 0, .68, 75, 0, .28, -.54, .13, -.28, -.54, .13, 1, 1, .08, -.03]),
    (1, [0, 0, .27, 86, 0, 2, -8, .65, 75, 0, .68, 75, 0, .28, -.54, .13, -.28, -.54, .13, 1, 1, .015, -.015]),
]


def build_pose(values, breath=0):
    for bone in rig.pose.bones:
        bone.matrix_basis = idle[bone.name]
    hips = idle_global["Hips"].copy()
    hips.translation = Vector(values[:3])
    rotation = Quaternion((0, 1, 0), math.radians(values[4])) @ Quaternion((1, 0, 0), math.radians(values[3]))
    hips = Matrix.Translation(hips.translation) @ rotation.to_matrix().to_4x4() @ Matrix.Translation(-hips.translation) @ hips
    rig.pose.bones["Hips"].matrix = hips
    bpy.context.view_layer.update()
    for name in ["Spine", "Spine1", "Spine2"]:
        local_rotation(name, values[5] / 3 + breath)
    local_rotation("Neck", values[6] * .55, 0, 5)
    local_rotation("Head", values[6] * .45, 0, -3)
    bpy.context.view_layer.update()
    hand_errors = [hand("Left", values[13:16], values[19]), hand("Right", values[16:19], values[20])]
    foot_errors = [foot("Left", *values[7:10], values[21] if len(values)>21 else .015), foot("Right", *values[10:13], values[22] if len(values)>22 else -.015)]
    return max(foot_errors), max(hand_errors)


def blend_basis(target, amount):
    for bone in rig.pose.bones:
        origin, rotation, scale = bone.matrix_basis.decompose()
        end_origin, end_rotation, end_scale = target[bone.name].decompose()
        bone.matrix_basis = Matrix.LocRotScale(origin.lerp(end_origin, amount), rotation.slerp(end_rotation, amount), scale.lerp(end_scale, amount))
    bpy.context.view_layer.update()


clips = [("Zombie_Sleep_Seated", 4.0, SEATED_WAKE, True, False),
         ("Zombie_Wake_Seated", 3.2, SEATED_WAKE, False, False),
         ("Zombie_Sleep_Lying", 4.0, LYING_WAKE, True, False),
         ("Zombie_Wake_Lying", 4.2, LYING_WAKE, False, False),
         ("Zombie_Wake_Seated_Crawl", 2.8, SEATED_CRAWL, False, True),
         ("Zombie_Wake_Lying_Crawl", 2.6, LYING_WAKE, False, True)]
scene.render.fps = 60
scene.frame_start = 0
scene.frame_end = 252
metadata = {"license": "CC0-1.0", "source": str(SOURCE.relative_to(ROOT)), "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(), "blender": bpy.app.version_string, "authoring": "Original Codex-authored key poses and IK trajectories; retained R4 rig and meshes keep their provenance", "fps": 60, "clips": []}
rig.animation_data_create()
for name, duration, trajectory, sleeping, crawling in clips:
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    end_frame = round(duration * 60)
    samples = []
    for frame_number in range(end_frame + 1):
        scene.frame_set(frame_number)
        phase = frame_number / end_frame
        values = trajectory[0][1] if sleeping or (crawling and trajectory is LYING_WAKE) else sample(phase, trajectory)
        foot_error, hand_error = build_pose(values, .16 * math.sin(math.tau * phase) if sleeping else 0)
        if crawling:
            start = .80 if trajectory is SEATED_CRAWL else .12
            amount = max(0.0, min(1.0, (phase - start) / (1.0 - start)))
            blend_basis(crawl, amount * amount * (3 - 2 * amount))
            if trajectory is LYING_WAKE and 0 < amount < 1:
                for prefix in ["Left", "Right"]:
                    matrix = rig.pose.bones[prefix + "Hand"].matrix.copy()
                    target = matrix.translation + Vector((0, 0, .04 * math.sin(math.pi * amount) ** 2))
                    pole = rig.pose.bones[prefix + "ForeArm"].head.copy()
                    target, _ = solve_chain(prefix + "Arm", prefix + "ForeArm", target, pole)
                    matrix.translation = target
                    rig.pose.bones[prefix + "Hand"].matrix = matrix
                    bpy.context.view_layer.update()
        elif not sleeping and phase > .82:
            amount = (phase - .82) / .18
            blend_basis(idle, amount * amount * (3 - 2 * amount))
        for bone in rig.pose.bones:
            bone.keyframe_insert("location", frame=frame_number, group=bone.name)
            bone.keyframe_insert("rotation_quaternion", frame=frame_number, group=bone.name)
            bone.keyframe_insert("scale", frame=frame_number, group=bone.name)
        samples.append({"frame": frame_number, "foot_target_error": foot_error, "hand_target_error": hand_error, "head": list(rig.pose.bones["Head"].head)})
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = "LINEAR"
    metadata["clips"].append({"name": name, "duration": duration, "loop": sleeping, "crawl_exit": crawling, "max_foot_target_error": max(row["foot_target_error"] for row in samples), "max_hand_target_error": max(row["hand_target_error"] for row in samples), "samples": samples})

for obj in list(bpy.data.objects):
    if obj.type in ["LIGHT", "CAMERA"] or obj.name.startswith("Preview."):
        bpy.data.objects.remove(obj, do_unlink=True)
    elif obj.name.startswith("Z_Cap_"):
        obj.hide_render = True
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.data.objects["Z_Torso"].select_set(True)
bpy.context.view_layer.objects.active = rig
scene.frame_set(0)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT / "Zombie.sleepers.glb"), export_format="GLB", use_selection=True,
    export_materials="NONE", export_animations=True, export_animation_mode="ACTIONS", export_frame_range=False,
    export_force_sampling=True, export_skins=True, export_morph=False, export_yup=True)
(OUTPUT / "Zombie.sleepers.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / "Zombie.sleepers.blend"), compress=True)
print("ZOMBIE_SLEEPERS_AUTHORED", [(clip["name"], clip["max_foot_target_error"], clip["max_hand_target_error"]) for clip in metadata["clips"]])
