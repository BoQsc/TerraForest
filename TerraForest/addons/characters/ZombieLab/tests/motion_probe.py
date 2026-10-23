"""Read-only animation measurements; Blender bundled Python only.

blender -b source/Zombie.blend --python motion_probe.py -- --output report.json
Use --baseline baseline.json to compare geometry, bind skeleton and motion ranges.
These measurements describe motion; they are not a substitute for visual review.
"""
import argparse
import bpy
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys


parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--baseline', type=Path)
parser.add_argument('--step', type=float, default=0.5)
parser.add_argument('--walk-speed', type=float, default=0.72)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
if args.step <= 0:
    parser.error('--step must be positive')

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pose_sampling import select_pose_action

scene = bpy.context.scene
rig = next(ob for ob in bpy.data.objects if ob.type == 'ARMATURE')
for track in rig.animation_data.nla_tracks:
    track.mute = True
mesh_objects = sorted((ob for ob in bpy.data.objects if ob.type == 'MESH' and ob.name.startswith('Z_')), key=lambda ob: ob.name)
parts = [ob for ob in mesh_objects if not ob.name.startswith('Z_Cap_')]


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def vec(value):
    return [float(x) for x in value]


def matrix(value):
    return [vec(row) for row in value]


def distance(a, b):
    return math.sqrt(sum((x-y)**2 for x, y in zip(a, b)))


def angle(a, b):
    return math.degrees(a.normalized().angle(b.normalized()))


def rounded(value):
    return tuple(round(float(x) * 1000000) for x in value)


def extrema(values):
    return {'minimum': min(values), 'maximum': max(values), 'range': max(values)-min(values)}


mesh_identity = {}
seam_groups = {}
for ob in mesh_objects:
    mesh = ob.data
    mesh.calc_loop_triangles()
    group_names = {g.index: g.name for g in ob.vertex_groups}
    data = {
        'coordinates': [vec(v.co) for v in mesh.vertices],
        'triangles': [list(t.vertices) for t in mesh.loop_triangles],
        'materials': [m.name if m else '' for m in mesh.materials],
        'face_materials': [p.material_index for p in mesh.polygons],
        'weights': [[(group_names[g.group], g.weight) for g in v.groups] for v in mesh.vertices],
        'uv_maps': {layer.name: [vec(row.uv) for row in layer.data] for layer in mesh.uv_layers},
        'matrix_world': matrix(ob.matrix_world),
    }
    mesh_identity[ob.name] = {'sha256': digest(data), 'vertices': len(mesh.vertices), 'triangles': len(mesh.loop_triangles)}
    if ob in parts:
        for vertex in mesh.vertices:
            seam_groups.setdefault(rounded(ob.matrix_world @ vertex.co), {}).setdefault(ob.name, vertex.index)
shared_groups = [group for group in seam_groups.values() if len(group) > 1]
maximum_skin_influences = max(sum(group.weight > 0.0 for group in vertex.groups)
    for ob in mesh_objects for vertex in ob.data.vertices)
rest = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones}
rest_identity = digest({bone.name: {'matrix': matrix(bone.matrix_local), 'length': bone.length,
                                   'parent': bone.parent.name if bone.parent else None}
                        for bone in rig.data.bones})
image_identity = sorted([{'name': im.name, 'packed': bool(im.packed_file),
                         'sha256': hashlib.sha256(bytes(im.packed_file.data)).hexdigest() if im.packed_file else None}
                        for im in bpy.data.images if im.source == 'FILE'], key=lambda row: row['name'])

tracked = ['Hips', 'Spine2', 'Head'] + [prefix + name for prefix in ('Left', 'Right')
    for name in ('Arm', 'ForeArm', 'Hand', 'UpLeg', 'Leg', 'Foot', 'ToeBase')]
report = {
    'source': bpy.data.filepath,
    'source_sha256': hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
    'fps': scene.render.fps,
    'step_frames': args.step,
    'coordinates': 'Blender meters: +X left, -Y forward, +Z up',
    'mesh_identity': mesh_identity,
    'rest_skeleton_sha256': rest_identity,
    'bone_count': len(rest),
    'maximum_positive_skin_influences': maximum_skin_influences,
    'file_images': image_identity,
    'shared_rest_vertex_groups': len(shared_groups),
    'clips': {},
    'limits': [
        'Motion amplitudes and speeds are descriptive, not an artistic quality score.',
        'No claim about unsampled times; frame and midpoint spacing are recorded.',
        'Ground-slip estimate uses each skinned sole vertex within 8 mm of Z=0 and an ideal constant forward body speed.',
        'Foot roll can move some sole vertices while the actual contact edge stays planted.',
        'Loop velocity mismatches are reported separately from exact endpoint pose continuity.',
    ],
}
global_checks = {'finite_transforms': True, 'unit_bone_scale_within_1e_4': True, 'coincident_seams_within_1e_5_m': True,
    'at_most_four_positive_skin_influences': maximum_skin_influences <= 4}

for action in sorted((a for a in bpy.data.actions if a.name.startswith('Zombie_')), key=lambda a: a.name):
    select_pose_action(rig, action)
    start, end = action.frame_range
    count = int(round((end-start)/args.step))+1
    samples = []
    maximum_scale_error = 0.0
    maximum_seam_error = 0.0
    all_finite = True
    for index in range(count):
        frame = start + index*args.step
        scene.frame_set(math.floor(frame), subframe=frame-math.floor(frame))
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        positions = {name: vec(rig.matrix_world @ rig.pose.bones[name].head) for name in tracked}
        rotations = {name: vec(rig.pose.bones[name].matrix.to_quaternion()) for name in tracked}
        for pb in rig.pose.bones:
            all_finite &= all(math.isfinite(v) for row in pb.matrix for v in row)
            maximum_scale_error = max(maximum_scale_error, max(abs(v-1.0) for v in pb.scale))
        evaluated_positions = {}
        for ob in parts:
            evaluated = ob.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            evaluated_positions[ob.name] = [evaluated.matrix_world @ v.co for v in mesh.vertices]
            evaluated.to_mesh_clear()
        for group in shared_groups:
            coordinates = [evaluated_positions[name][vertex_index] for name, vertex_index in group.items()]
            maximum_seam_error = max(maximum_seam_error, max((p-coordinates[0]).length for p in coordinates[1:]))
        angles = {}
        feet = {}
        for prefix, suffix in [('Left', 'L'), ('Right', 'R')]:
            upper = rig.pose.bones[prefix+'Arm']
            forearm = rig.pose.bones[prefix+'ForeArm']
            hand = rig.pose.bones[prefix+'Hand']
            thigh = rig.pose.bones[prefix+'UpLeg']
            shin = rig.pose.bones[prefix+'Leg']
            angles[prefix+'_elbow_flexion_deg'] = angle(forearm.head-upper.head, hand.head-forearm.head)
            angles[prefix+'_knee_flexion_deg'] = angle(shin.head-thigh.head, rig.pose.bones[prefix+'Foot'].head-shin.head)
            neutral = rest[prefix+'ForeArm'].inverted() @ rest[prefix+'Hand']
            relative = forearm.matrix.inverted() @ hand.matrix
            delta = relative.to_quaternion() @ neutral.to_quaternion().inverted()
            angles[prefix+'_wrist_relative_rotation_deg'] = math.degrees(min(delta.angle, math.tau-delta.angle))
            feet[prefix] = [vec(v) for v in evaluated_positions['Z_Foot_'+suffix]]
        samples.append({'frame': frame, 'time_seconds': (frame-start)/scene.render.fps,
                        'positions_blender_m': positions, 'rotations_quat_wxyz': rotations,
                        'angles': angles, '_feet': feet})
    ranges = {}
    speeds = {}
    for name in tracked:
        values = [row['positions_blender_m'][name] for row in samples]
        ranges[name] = {axis: extrema([p[index] for p in values]) for index, axis in enumerate(('x', 'y', 'z'))}
        derivative = [distance(a, b)/(args.step/scene.render.fps) for a, b in zip(values, values[1:])]
        speeds[name] = {'maximum_m_s': max(derivative), 'average_m_s': statistics.mean(derivative)}
    loop_position = max(distance(samples[0]['positions_blender_m'][name], samples[-1]['positions_blender_m'][name]) for name in tracked)
    loop_velocity = {}
    dt = args.step/scene.render.fps
    for name in tracked:
        first = [(b-a)/dt for a,b in zip(samples[0]['positions_blender_m'][name], samples[1]['positions_blender_m'][name])]
        last = [(b-a)/dt for a,b in zip(samples[-2]['positions_blender_m'][name], samples[-1]['positions_blender_m'][name])]
        loop_velocity[name] = distance(first, last)
    foot_stats = {}
    for prefix in ('Left', 'Right'):
        minimum_z = min(v[2] for row in samples for v in row['_feet'][prefix])
        maximum_minimum_z = max(min(v[2] for v in row['_feet'][prefix]) for row in samples)
        contact_slip = []
        contact_edge_slip = []
        contact_speed = []
        contact_intervals = 0
        for before, after in zip(samples, samples[1:]):
            points = list(zip(before['_feet'][prefix], after['_feet'][prefix]))
            contact = [(a,b) for a,b in points if abs(a[2])<=0.008 and abs(b[2])<=0.008]
            if not contact:
                continue
            contact_intervals += 1
            contact_speed.extend((b[1]-a[1])/dt for a,b in contact)
            forward_speed = args.walk_speed if action.name == 'Zombie_Walk' else 0.0
            contact_slip.extend(math.hypot((b[0]-a[0])/dt, (b[1]-a[1])/dt-forward_speed) for a,b in contact)
            edge_before, edge_after = min(contact, key=lambda pair: max(abs(pair[0][2]), abs(pair[1][2])))
            contact_edge_slip.append(math.hypot((edge_after[0]-edge_before[0])/dt,
                                               (edge_after[1]-edge_before[1])/dt-forward_speed))
        foot_stats[prefix] = {'minimum_surface_z_m': minimum_z, 'maximum_sole_minimum_z_m': maximum_minimum_z,
            'near_ground_intervals': contact_intervals,
            'reference_body_forward_speed_m_s': args.walk_speed if action.name=='Zombie_Walk' else 0.0,
            'near_ground_vertex_speed_y_median_m_s': statistics.median(contact_speed) if contact_speed else None,
            'near_ground_vertex_slip_median_m_s': statistics.median(contact_slip) if contact_slip else None,
            'near_ground_vertex_slip_p90_m_s': sorted(contact_slip)[int(0.9*(len(contact_slip)-1))] if contact_slip else None,
            'closest_contact_edge_slip_median_m_s': statistics.median(contact_edge_slip) if contact_edge_slip else None,
            'closest_contact_edge_slip_p90_m_s': sorted(contact_edge_slip)[int(0.9*(len(contact_edge_slip)-1))] if contact_edge_slip else None,
            'closest_contact_edge_slip_max_m_s': max(contact_edge_slip) if contact_edge_slip else None}
    for row in samples:
        del row['_feet']
    checks = {'finite_transforms': all_finite,
        'unit_bone_scale_within_1e_4': maximum_scale_error < 1e-4,
        'coincident_seams_within_1e_5_m': maximum_seam_error < 1e-5}
    for name, value in checks.items():
        global_checks[name] &= value
    report['clips'][action.name] = {'start_frame': start, 'end_frame': end, 'samples': len(samples),
        'duration_seconds': (end-start)/scene.render.fps, 'checks': checks,
        'maximum_bone_scale_error': maximum_scale_error, 'maximum_seam_separation_m': maximum_seam_error,
        'position_ranges_m': ranges, 'linear_speeds': speeds,
        'angle_ranges_deg': {name: extrema([row['angles'][name] for row in samples]) for name in samples[0]['angles']},
        'endpoint_tracked_position_difference_m': loop_position, 'endpoint_velocity_difference_m_s': loop_velocity,
        'feet': foot_stats, 'frames': samples}
    print('MOTION_PROBE', action.name, count, 'samples', 'seam_error_m', maximum_seam_error, flush=True)

if args.baseline:
    baseline = json.loads(args.baseline.read_text())
    comparison = {'baseline_source_sha256': baseline['source_sha256'],
        'geometry_and_weights_identical': baseline['mesh_identity'] == mesh_identity,
        'rest_skeleton_identical': baseline['rest_skeleton_sha256'] == rest_identity,
        'packed_images_identical': baseline['file_images'] == image_identity,
        'clips': {}}
    for clip, after in report['clips'].items():
        before = baseline['clips'].get(clip)
        if before is None:
            continue
        comparison['clips'][clip] = {name: {axis: {'before_range_m': before['position_ranges_m'][name][axis]['range'],
                    'after_range_m': after['position_ranges_m'][name][axis]['range']}
                    for axis in ('x','y','z')} for name in ('Hips','Spine2','Head','LeftHand','RightHand','LeftFoot','RightFoot')}
    report['comparison'] = comparison
report['checks'] = global_checks
report['passed_structural_motion_checks'] = all(global_checks.values())
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2)+'\n')
print('MOTION_PROBE_COMPLETE', json.dumps({'passed_structural_motion_checks': report['passed_structural_motion_checks'],
    'source_sha256': report['source_sha256'], 'comparison': report.get('comparison', {})}), flush=True)

