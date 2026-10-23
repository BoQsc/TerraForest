"""Exact triangle-intersection audit of evaluated zombie animation meshes.

Run with Blender 4.5 or later, using its bundled Python only:
  blender -b ../source/Zombie.blend --python animation_mesh_check.py -- --skin-self
  blender -b /path/Zombie.blend --python /path/animation_mesh_check.py -- \
    --skin-self --output /path/animation_mesh_validation.json

The default output is animation_mesh_validation.json beside this script.
Default step 0.5 samples every authored 60 Hz frame and its midpoint (120 Hz).
The production gate includes all part pairs, skin versus clothing, whole-hand
self intersections, and --skin-self for other non-head anatomical meshes.
Use --all-body-self for additional unfiltered clothing-layer diagnostics; joined
trim, pockets and overlapping garment construction can then be reported.
No source file is changed. Hidden wound caps and head-internal self surfaces
are excluded. Adjacent parts are filtered only near their exact shared cut rims.
"""
import argparse
import bpy
import hashlib
import itertools
import json
import math
from pathlib import Path
import sys
import time
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree


parser = argparse.ArgumentParser()
parser.add_argument('--output', default=str(Path(__file__).resolve().with_name('animation_mesh_validation.json')))
parser.add_argument('--step', type=float, default=0.5)
parser.add_argument('--clips', nargs='*')
parser.add_argument('--all-body-self', action='store_true', help='Also check non-head anatomical meshes against themselves.')
parser.add_argument('--skin-self', action='store_true', help='Also check actual skin surfaces in every non-head body mesh against themselves.')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
if args.step <= 0:
    parser.error('--step must be positive')
started = time.time()
EPS = 1e-7
MIN_SEGMENT = 0.0005
SEAM_TOLERANCE = 0.015
sys.path.insert(0, str(Path(__file__).resolve().parent))
from pose_sampling import select_pose_action

scene = bpy.context.scene
rig = next(ob for ob in bpy.data.objects if ob.type == 'ARMATURE')
parts = sorted((ob for ob in bpy.data.objects if ob.type == 'MESH'
                and ob.name.startswith('Z_') and not ob.name.startswith('Z_Cap_')),
               key=lambda ob: ob.name)
for track in rig.animation_data.nla_tracks:
    track.mute = True

PARENT = {'Head': 'Torso'}
for side in ('L', 'R'):
    for child, parent in [('UpperArm', 'Torso'), ('Forearm', 'UpperArm'), ('Hand', 'Forearm'),
                          ('Thigh', 'Torso'), ('Shin', 'Thigh'), ('Foot', 'Shin')]:
        PARENT[child + '_' + side] = parent if parent == 'Torso' else parent + '_' + side
ADJACENT = {tuple(sorted(('Z_' + child, 'Z_' + parent))) for child, parent in PARENT.items()}


def rounded(v):
    return tuple(round(float(x) * 1000000) for x in v)


def bounds(verts):
    return ([min(v[a] for v in verts) for a in range(3)],
            [max(v[a] for v in verts) for a in range(3)])


def overlaps(a, b):
    return all(a[0][axis] <= b[1][axis] and b[0][axis] <= a[1][axis] for axis in range(3))


def inside_triangle(p, tri):
    a, b, c = tri
    u, v, w = b - a, c - a, p - a
    uu, uv, vv, wu, wv = u.dot(u), u.dot(v), v.dot(v), w.dot(u), w.dot(v)
    denominator = uu * vv - uv * uv
    if abs(denominator) < 1e-20:
        return False
    s, t = (vv * wu - uv * wv) / denominator, (uu * wv - uv * wu) / denominator
    return s >= -1e-6 and t >= -1e-6 and s + t <= 1.000001


def exact_intersection(a, b):
    na = (a[1] - a[0]).cross(a[2] - a[0])
    nb = (b[1] - b[0]).cross(b[2] - b[0])
    if na.length_squared < 1e-18 or nb.length_squared < 1e-18:
        return None
    na.normalize()
    nb.normalize()
    da = [(v - b[0]).dot(nb) for v in a]
    db = [(v - a[0]).dot(na) for v in b]
    if min(da) > EPS or max(da) < -EPS or min(db) > EPS or max(db) < -EPS:
        return None
    if max(abs(d) for d in da) < EPS and max(abs(d) for d in db) < EPS:
        return None  # Coplanar/tangent contacts are not asserted as penetration.
    shared = sum(any((p - q).length_squared < 1e-12 for q in b) for p in a)
    if shared >= 2:
        return None  # Exact shared edge, including coincident material seams.
    points = []
    for vertices, distances, other in [(a, da, b), (b, db, a)]:
        for index in range(3):
            p, q = vertices[index], vertices[(index + 1) % 3]
            d0, d1 = distances[index], distances[(index + 1) % 3]
            if abs(d0) <= EPS and inside_triangle(p, other):
                points.append(p.copy())
            if d0 * d1 < 0 and abs(d0 - d1) > EPS:
                hit = p + (q - p) * (d0 / (d0 - d1))
                if inside_triangle(hit, other):
                    points.append(hit)
    unique = []
    for p in points:
        if not any((p - q).length_squared < 1e-12 for q in unique):
            unique.append(p)
    if len(unique) < 2:
        return None
    length = max((p - q).length for p, q in itertools.combinations(unique, 2))
    if length < MIN_SEGMENT:
        return None
    depth_proxy = min(max(0.0, min(max(da), -min(da))), max(0.0, min(max(db), -min(db))))
    if depth_proxy <= EPS:
        return None  # One-sided contact within numeric epsilon is a tangency.
    return unique, length, depth_proxy


topology = {}
rest_positions = {}
for ob in parts:
    ob.data.calc_loop_triangles()
    tris = [tuple(tri.vertices) for tri in ob.data.loop_triangles]
    materials = [ob.data.materials[tri.material_index].name if ob.data.materials[tri.material_index] else ''
                 for tri in ob.data.loop_triangles]
    influences = []
    for vertex in ob.data.vertices:
        influences.append({ob.vertex_groups[g.group].name: g.weight for g in vertex.groups})
    owners = []
    for tri in tris:
        total = {}
        for index in tri:
            for bone, weight in influences[index].items():
                total[bone] = total.get(bone, 0.0) + weight
        owners.append(max(total, key=total.get) if total else '')
    groups = {}
    for index, material in enumerate(materials):
        groups.setdefault(material, []).append(index)
    topology[ob.name] = {'triangles': tris, 'materials': materials, 'owners': owners, 'groups': groups}
    rest_positions[ob.name] = {rounded(ob.matrix_world @ vertex.co): index for index, vertex in enumerate(ob.data.vertices)}

seam_indices = {}
for a, b in ADJACENT:
    shared = set(rest_positions[a]) & set(rest_positions[b])
    seam_indices[(a, b)] = [rest_positions[a][key] for key in shared]


def evaluated_parts():
    depsgraph = bpy.context.evaluated_depsgraph_get()
    result = {}
    for ob in parts:
        evaluated = ob.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        verts = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        evaluated.to_mesh_clear()
        topo = topology[ob.name]
        result[ob.name] = {'object_name': ob.name, 'vertices': verts, 'triangles': topo['triangles'],
                           'bvh': BVHTree.FromPolygons(verts, topo['triangles'], all_triangles=True, epsilon=0.0),
                           'bounds': bounds(verts)}
    return result


def collect_intersections(a, b, candidates, self_mesh=False):
    points = []
    maximum_segment, maximum_proxy = 0.0, 0.0
    valid = 0
    owners = {}
    examples = []
    for ia, ib in candidates:
        ta, tb = a['triangles'][ia], b['triangles'][ib]
        if self_mesh and (ia >= ib or set(ta) & set(tb)):
            continue
        if self_mesh and a.get('skin_self_only'):
            materials = topology[a['object_name']]['materials']
            skin = {'Zombie.Body.PBR', 'Zombie.Head.PBR', 'Zombie.Eyelid.Skin'}
            if materials[ia] not in skin or materials[ib] not in skin:
                continue
        tri_a, tri_b = [a['vertices'][i] for i in ta], [b['vertices'][i] for i in tb]
        contact = exact_intersection(tri_a, tri_b)
        if contact is None:
            continue
        intersection_points, segment, proxy = contact
        points.extend(intersection_points)
        valid += 1
        maximum_segment = max(maximum_segment, segment)
        maximum_proxy = max(maximum_proxy, proxy)
        if self_mesh:
            key = ' / '.join(sorted((a['owners'][ia], a['owners'][ib])))
            owners[key] = owners.get(key, 0) + 1
            if len(examples) < 16:
                original = bpy.data.objects[a['object_name']].data
                examples.append({'triangle_a': ia, 'triangle_b': ib,
                                 'vertex_indices_a': list(ta), 'vertex_indices_b': list(tb),
                                 'rest_vertices_a_blender_m': [list(original.vertices[i].co) for i in ta],
                                 'rest_vertices_b_blender_m': [list(original.vertices[i].co) for i in tb],
                                 'posed_vertices_a_blender_m': [list(v) for v in tri_a],
                                 'posed_vertices_b_blender_m': [list(v) for v in tri_b],
                                 'dominant_bones': [a['owners'][ia], a['owners'][ib]]})
    if not valid:
        return None
    minimum, maximum = bounds(points)
    return {'triangle_intersections': valid, 'max_intersection_segment_m': maximum_segment,
            'max_triangle_plane_penetration_proxy_m': maximum_proxy,
            'intersection_bounds_blender_m': [minimum, maximum],
            'intersection_extent_m': [hi - lo for lo, hi in zip(minimum, maximum)],
            'example_blender_m': list(points[0]), 'bone_pairs': owners, 'triangle_examples': examples,
            '_points': points}


def inspect_frame(frame_data):
    findings = []
    names = list(frame_data)
    for a_name, b_name in itertools.combinations(names, 2):
        a, b = frame_data[a_name], frame_data[b_name]
        if not overlaps(a['bounds'], b['bounds']):
            continue
        pairs = a['bvh'].overlap(b['bvh'])
        if not pairs:
            continue
        record = collect_intersections(a, b, pairs)
        if record is None:
            continue
        pair = tuple(sorted((a_name, b_name)))
        record.update({'category': 'nonadjacent_parts', 'pair': ' / '.join(pair), 'expected_contact': False})
        if pair in ADJACENT:
            record['category'] = 'adjacent_parts'
            indices = seam_indices[pair]
            if indices:
                tree = KDTree(len(indices))
                for index, vertex_index in enumerate(indices):
                    tree.insert(frame_data[pair[0]]['vertices'][vertex_index], index)
                tree.balance()
                furthest = max(tree.find(p)[2] for p in record['_points'])
                record['furthest_intersection_from_shared_seam_m'] = furthest
                record['expected_contact'] = furthest <= SEAM_TOLERANCE
        del record['_points']
        findings.append(record)
    for name, part in frame_data.items():
        topo = topology[name]
        body_materials = [m for m in topo['groups'] if m in ('Zombie.Body.PBR', 'Zombie.Head.PBR', 'Zombie.Eyelid.Skin')]
        clothing_materials = [m for m in topo['groups'] if 'Cloth.' in m]
        for body_mat, cloth_mat in itertools.product(body_materials, clothing_materials):
            ga, gb = topo['groups'][body_mat], topo['groups'][cloth_mat]
            a = {'vertices': part['vertices'], 'triangles': [part['triangles'][i] for i in ga]}
            b = {'vertices': part['vertices'], 'triangles': [part['triangles'][i] for i in gb]}
            ba = BVHTree.FromPolygons(a['vertices'], a['triangles'], all_triangles=True)
            bb = BVHTree.FromPolygons(b['vertices'], b['triangles'], all_triangles=True)
            record = collect_intersections(a, b, ba.overlap(bb))
            if record:
                del record['_points']
                record.update({'category': 'body_clothing', 'pair': name + ': ' + body_mat + ' / ' + cloth_mat,
                               'expected_contact': False})
                findings.append(record)
        if name.startswith('Z_Hand_') or ((args.all_body_self or args.skin_self) and name != 'Z_Head'):
            part['owners'] = topo['owners']
            part['skin_self_only'] = args.skin_self and not args.all_body_self and not name.startswith('Z_Hand_')
            record = collect_intersections(part, part, part['bvh'].overlap(part['bvh']), self_mesh=True)
            if record:
                del record['_points']
                record.update({'category': 'hand_self' if name.startswith('Z_Hand_') else ('skin_self' if part['skin_self_only'] else 'body_self'),
                               'pair': name, 'expected_contact': False})
                findings.append(record)
    return findings


actions = [action for action in bpy.data.actions if action.name.startswith('Zombie_')
           and (not args.clips or action.name in args.clips)]
actions.sort(key=lambda action: {'Zombie_Hit': 0, 'Zombie_Attack': 1, 'Zombie_Idle': 2, 'Zombie_Walk': 3}.get(action.name, 4))
samples = []
summary = {}
source = Path(bpy.data.filepath)
report = {'source': str(source), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
          'fps': scene.render.fps, 'step_frames': args.step, 'seam_contact_tolerance_m': SEAM_TOLERANCE,
          'minimum_reported_intersection_segment_m': MIN_SEGMENT,
          'numeric_plane_epsilon_m': EPS,
          'method': 'Blender evaluated armature meshes, BVH broad phase and exact noncoplanar triangle-plane segment checks',
          'coverage': ['all anatomical part pairs including adjacency away from cut seams',
                       'body versus clothing materials within every part',
                       'hand self-intersections excluding triangles sharing a vertex, labeled by dominant bone'],
          'limits': ['no claim about unsampled times', 'coplanar/tangent contacts excluded',
                     'triangle plane penetration is a local proxy, not a volumetric signed distance',
                     'hidden wound caps excluded', 'self-test triangle pairs sharing any vertex excluded',
                     'head internal surfaces such as teeth, eyes and mouth are not self-tested',
                     'same-part clothing-layer self contacts are outside --skin-self coverage; --all-body-self reports them unfiltered'],
          'clips': [], 'pair_summary': summary, 'samples': samples}
if args.all_body_self:
    report['coverage'].append('every non-head body mesh against itself, excluding triangles sharing a vertex')
    report['limits'].append('unfiltered clothing-layer intersections may describe original trim, pockets or garment construction')
if args.skin_self:
    report['coverage'].append('actual skin surfaces within every non-head mesh checked for self-folds, excluding shared-vertex triangle pairs')


expected_total_samples = sum(int(round((action.frame_range[1] - action.frame_range[0]) / args.step)) + 1 for action in actions)


def write_report():
    report['elapsed_wall_seconds'] = time.time() - started
    report['sample_count'] = len(samples)
    report['samples_with_unexpected_intersections'] = sum(any(not f['expected_contact'] for f in s['findings']) for s in samples)
    report['expected_sample_count'] = expected_total_samples
    report['completed'] = bool(actions) and len(samples) == expected_total_samples and len(report['clips']) == len(actions)
    report['passed'] = report['completed'] and report['samples_with_unexpected_intersections'] == 0
    report['summary'] = {'requested_clips': [a.name for a in actions], 'completed_samples': len(samples),
                       'expected_samples': expected_total_samples, 'unexpected_samples': report['samples_with_unexpected_intersections'],
                       'skin_self_enabled': args.skin_self, 'all_body_self_enabled': args.all_body_self,
                       'expected_shared_seam_findings_preserved': True}
    if samples:
        report['animated_world_bounds_blender_m'] = [[min(sample['world_bounds_blender_m'][0][axis] for sample in samples) for axis in range(3)],
                                                   [max(sample['world_bounds_blender_m'][1][axis] for sample in samples) for axis in range(3)]]
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(report, indent=2) + '\n')


for action in actions:
    select_pose_action(rig, action)
    start, end = action.frame_range
    count = int(round((end - start) / args.step)) + 1
    clip_stats = {'name': action.name, 'start_frame': start, 'end_frame': end,
                  'expected_samples': count, 'completed_samples': 0}
    report['clips'].append(clip_stats)
    for sample_index in range(count):
        frame = start + sample_index * args.step
        scene.frame_set(math.floor(frame), subframe=frame - math.floor(frame))
        bpy.context.view_layer.update()
        frame_data = evaluated_parts()
        findings = inspect_frame(frame_data)
        world_bounds = [[min(part['bounds'][0][axis] for part in frame_data.values()) for axis in range(3)],
                        [max(part['bounds'][1][axis] for part in frame_data.values()) for axis in range(3)]]
        sample = {'clip': action.name, 'frame': frame, 'time_seconds': frame / scene.render.fps,
                  'world_bounds_blender_m': world_bounds, 'findings': findings}
        samples.append(sample)
        clip_stats['completed_samples'] += 1
        for finding in findings:
            key = finding['category'] + ': ' + finding['pair']
            entry = summary.setdefault(key, {'samples': 0, 'unexpected_samples': 0, 'max_triangle_intersections': 0,
                                             'max_plane_penetration_proxy_m': 0.0, 'worst': None})
            entry['samples'] += 1
            entry['unexpected_samples'] += int(not finding['expected_contact'])
            metric = finding['triangle_intersections']
            if metric > entry['max_triangle_intersections']:
                entry['max_triangle_intersections'] = metric
                entry['worst'] = {'clip': action.name, 'frame': frame, 'time_seconds': frame / scene.render.fps, **finding}
            if not finding['expected_contact'] and (entry.get('worst_unexpected') is None
                    or metric > entry['worst_unexpected']['triangle_intersections']):
                entry['worst_unexpected'] = {'clip': action.name, 'frame': frame, 'time_seconds': frame / scene.render.fps, **finding}
            entry['max_plane_penetration_proxy_m'] = max(entry['max_plane_penetration_proxy_m'], finding['max_triangle_plane_penetration_proxy_m'])
        if sample_index % 24 == 0:
            write_report()
            unexpected = [f for f in findings if not f['expected_contact']]
            print('QA_FRAME', action.name, frame, 'unexpected',
                  [(f['pair'], f['triangle_intersections'], [round(v, 4) for v in f['intersection_extent_m']]) for f in unexpected], flush=True)
    write_report()
    print('QA_CLIP_COMPLETE', action.name, count, 'samples', flush=True)
write_report()
print('QA_AUDIT_COMPLETE', report['sample_count'], 'samples', report['samples_with_unexpected_intersections'], 'with intersections', flush=True)

print('QA_GATE_RESULT', json.dumps({'passed': report['passed'], **report['summary']}), flush=True)
if not report['passed']:
    raise RuntimeError('Animation mesh audit failed; see the JSON report for sampled intersections or incomplete coverage.')
