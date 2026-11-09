# SPDX-License-Identifier: CC0-1.0
"""Actual evaluated skin/weapon contact diagnostics; no source mutations.

Uses Blender's native BVH/mathutils and Python standard library. Signed
nearest-normal distances are reported only as auxiliary information. Inside
classification uses repeated ray parity for individually closed components,
so open meshes and overlapping disconnected solids are not silently treated
as a single watertight volume. Analysis welding never edits the source mesh.
"""
import bpy
import math
from collections import defaultdict, deque
from mathutils import Vector, Quaternion
from mathutils.bvhtree import BVHTree

RAYS = [Vector(v).normalized() for v in ((1,.371,.217),(-.193,1,.413),(.277,-.329,1),
                                        (-1,.529,-.337),(.463,-1,-.719))]
FAMILIES = ('Middle','Ring','Pinky')


def evaluated_mesh(obj, to_space):
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    matrix = to_space @ evaluated.matrix_world
    points = [matrix @ vertex.co for vertex in mesh.vertices]
    faces = [tuple(triangle.vertices) for triangle in mesh.loop_triangles]
    evaluated.to_mesh_clear()
    return points, faces


class MeshVolume:
    def __init__(self, points, faces, name='Frame'):
        self.name = name
        self.points = points
        self.faces = faces
        self.bvh = BVHTree.FromPolygons(points, faces, all_triangles=True, epsilon=0.0)
        # Position-only welding resolves rendering splits while preserving
        # independent coordinates in all reported source vertex records.
        lookup = {}; mapping = []; welded = []
        for p in points:
            key = tuple(round(value / 1e-7) for value in p)
            if key not in lookup:
                lookup[key] = len(welded); welded.append(p)
            mapping.append(lookup[key])
        topology_faces = [tuple(mapping[i] for i in face) for face in faces]
        edge_faces = defaultdict(list)
        for index, face in enumerate(topology_faces):
            for a,b in ((face[0],face[1]),(face[1],face[2]),(face[2],face[0])):
                edge_faces[tuple(sorted((a,b)))].append(index)
        adjacency = [set() for face in faces]
        for shared in edge_faces.values():
            for a in shared:
                adjacency[a].update(b for b in shared if b != a)
        remaining = set(range(len(faces))); self.components = []; details = []
        while remaining:
            pending = [remaining.pop()]; group=[]
            while pending:
                index=pending.pop(); group.append(index)
                added=adjacency[index] & remaining
                remaining.difference_update(added); pending.extend(added)
            selected=set(group); component_edges={edge:indices for edge,indices in edge_faces.items()
                                                   if any(index in selected for index in indices)}
            boundary=sum(len(indices)==1 for indices in component_edges.values())
            nonmanifold=sum(len(indices)>2 for indices in component_edges.values())
            cfaces=[faces[index] for index in group]
            ids=set(i for face in cfaces for i in face)
            lo=Vector(tuple(min(points[i][axis] for i in ids) for axis in range(3)))
            hi=Vector(tuple(max(points[i][axis] for i in ids) for axis in range(3)))
            signed_volume=sum(points[a].dot(points[b].cross(points[c])) for a,b,c in cfaces)/6
            component={'indices':group,'faces':cfaces,'lo':lo,'hi':hi,'closed':boundary==0 and nonmanifold==0,
                       'bvh':BVHTree.FromPolygons(points,cfaces,all_triangles=True,epsilon=0.0)}
            self.components.append(component)
            details.append({'triangles':len(group),'boundary_edges':boundary,'nonmanifold_edges':nonmanifold,
                            'signed_volume_m3':signed_volume,'bounds_mm':[list(lo*1000),list(hi*1000)],
                            'closed_for_parity':component['closed']})
        self.topology={'mesh':name,'vertices':len(points),'analysis_welded_vertices':len(welded),
                       'triangles':len(faces),'components':details,
                       'all_components_closed':all(c['closed'] for c in self.components)}

    @staticmethod
    def _parity(point, direction, component):
        origin=point.copy(); maximum=(component['hi']-component['lo']).length*3+1
        count=0; travelled=0.0
        for _ in range(128):
            hit,normal,index,distance=component['bvh'].ray_cast(origin,direction,maximum-travelled)
            if hit is None:return count%2
            count+=1; travelled+=distance+2e-7
            origin=hit+direction*2e-7
        return None

    def probe(self, point, rays=3):
        nearest,normal,face,distance=self.bvh.find_nearest(point)
        if nearest is None:return {'inside':None,'reason':'No surface'}
        inside_components=[]; inconsistent=[]; open_possible=[]
        for number,component in enumerate(self.components):
            if any(point[axis]<component['lo'][axis]-1e-7 or point[axis]>component['hi'][axis]+1e-7 for axis in range(3)):
                continue
            if not component['closed']:
                open_possible.append(number); continue
            votes=[self._parity(point,d,component) for d in RAYS[:rays]]
            if len(set(votes))>1 or None in votes:inconsistent.append({'component':number,'votes':votes})
            if sum(v==1 for v in votes)>len(votes)/2:inside_components.append(number)
        inside=bool(inside_components)
        if not inside and open_possible:inside=None
        return {'inside':inside,'inside_components':inside_components,'ray_disagreement':inconsistent,
                'open_components_nearby':open_possible,'nearest_distance_mm':distance*1000,
                'nearest_normal_signed_mm':(point-nearest).dot(normal)*1000,
                'nearest_point_mm':list(nearest*1000),'nearest_face':face}

    def winding(self, point, component_index):
        """Independent solid-angle check for selected suspect points."""
        total=0.0
        for a,b,c in self.components[component_index]['faces']:
            va,vb,vc=(self.points[i]-point for i in (a,b,c))
            la,lb,lc=va.length,vb.length,vc.length
            numerator=va.dot(vb.cross(vc))
            denominator=la*lb*lc+va.dot(vb)*lc+vb.dot(vc)*la+vc.dot(va)*lb
            total+=2*math.atan2(numerator,denominator)
        return total/(4*math.pi)

    def outer_grip_span(self, point):
        """Rendered outer-grip span, including the open frontstrap strips.

        This is explicitly an envelope test, not a watertight-volume claim.
        Each X and Y interval is bracketed by actual opposite-side triangle
        ray hits at this point's other coordinates. Restrict to the grip;
        trigger-guard holes are outside the useful domain.
        """
        if not (-.135 <= point.y <= -.030 and -.080 <= point.z <= .008):
            return {'inside_outer_grip':False,'valid':False}
        spans=[]
        for axis,limit in ((0,.08),(1,.18)):
            a=point.copy();b=point.copy();a[axis]=limit;b[axis]=-limit
            direction=Vector((0,0,0));direction[axis]=-1
            high=self.bvh.ray_cast(a,direction,limit*2)[0]
            low=self.bvh.ray_cast(b,-direction,limit*2)[0]
            if high is None or low is None:return {'inside_outer_grip':False,'valid':False}
            spans.append((low[axis],high[axis],min(point[axis]-low[axis],high[axis]-point[axis])))
        return {'inside_outer_grip':all(row[2]>1e-7 for row in spans),'valid':True,
                'span_depth_mm':min(row[2]for row in spans)*1000,
                'x_interval_mm':[spans[0][0]*1000,spans[0][1]*1000],
                'y_interval_mm':[spans[1][0]*1000,spans[1][1]*1000]}


def finger_regions(body, families=FAMILIES):
    result={family:set() for family in families}
    source_weights=[]
    for vertex in body.data.vertices:
        weights={body.vertex_groups[g.group].name:float(g.weight) for g in vertex.groups}
        source_weights.append(weights)
        masses={family:sum(value for name,value in weights.items() if name.startswith('RightHand'+family))
                for family in ('Index','Middle','Ring','Pinky','Thumb')}
        family=max(masses,key=masses.get)
        if family in result and masses[family]>=.45:
            result[family].add(vertex.index)
    return result,source_weights


def surface_samples(points, faces, regions, mode='vertices'):
    result={family:[] for family in regions}
    for family,indices in regions.items():
        result[family].extend({'kind':'vertex','vertex':i,'point':points[i]} for i in sorted(indices))
        if mode=='vertices':continue
        for number,face in enumerate(faces):
            if sum(index in indices for index in face)<2:continue
            a,b,c=(points[index] for index in face)
            barycentrics=[(1/3,1/3,1/3),(.5,.5,0),(.5,0,.5),(0,.5,.5)]
            if mode=='dense':
                longest=max((a-b).length,(a-c).length,(b-c).length)
                n=min(12,max(2,math.ceil(longest/.0025)))
                barycentrics=[(i/n,j/n,(n-i-j)/n) for i in range(n+1) for j in range(n+1-i)]
            result[family].extend({'kind':'surface','triangle':number,'source_vertices':list(face),
                'barycentric':list(w),'point':a*w[0]+b*w[1]+c*w[2]}for w in barycentrics)
    return result


def summarize_samples(samples, volume, rays=3):
    result={}
    for family,items in samples.items():
        embedded=[]; outside=[]; unknown=0; disagreement=0; envelope=[]; distal_gaps=[]; distal_inside=0;contact_regions={}
        for sample in items:
            finding=volume.probe(sample['point'],rays)
            span=volume.outer_grip_span(sample['point'])
            if 'contact_region'in sample:
                region=contact_regions.setdefault(sample['contact_region'],{'samples':0,'closed_max_mm':0,'outer_span_max_mm':0})
                region['samples']+=1
                if finding['inside']is True:region['closed_max_mm']=max(region['closed_max_mm'],finding['nearest_distance_mm'])
                if span['inside_outer_grip']:region['outer_span_max_mm']=max(region['outer_span_max_mm'],span['span_depth_mm'])
            if span['inside_outer_grip']:
                envelope.append({**{k:v for k,v in sample.items()if k!='point'},
                    'position_item_mm':list(sample['point']*1000),**finding,**span})
            if sample.get('joint')==3:
                if finding['inside'] or span['inside_outer_grip']:distal_inside+=1
                else:distal_gaps.append(finding['nearest_distance_mm'])
            disagreement+=bool(finding.get('ray_disagreement'))
            if finding['inside'] is None:unknown+=1
            elif finding['inside']:
                embedded.append({**{k:v for k,v in sample.items() if k!='point'},
                                 'position_item_mm':list(sample['point']*1000),**finding})
            else:outside.append(finding['nearest_distance_mm'])
        embedded.sort(key=lambda row:row['nearest_distance_mm'],reverse=True)
        envelope.sort(key=lambda row:row['nearest_distance_mm'],reverse=True)
        result[family]={'samples':len(items),'inside_samples':len(embedded),'unknown_samples':unknown,
                        'ray_disagreement_samples':disagreement,
                        'deep_samples_over_2mm':sum(row['nearest_distance_mm']>2 for row in embedded),
                        'deep_samples_over_5mm':sum(row['nearest_distance_mm']>5 for row in embedded),
                        'max_inside_distance_mm':embedded[0]['nearest_distance_mm']if embedded else 0,
                        'inside_depth_sum_mm':sum(row['nearest_distance_mm']for row in embedded),
                        'outside_min_distance_mm':min(outside,default=None),'deepest':embedded[:24],
                        'outer_grip_inside_samples':len(envelope),
                        'outer_grip_max_nearest_surface_distance_mm':envelope[0]['nearest_distance_mm']if envelope else 0,
                        'outer_grip_max_orthogonal_exit_mm':max((row['span_depth_mm']for row in envelope),default=0),
                        'outer_grip_deepest':envelope[:12],
                        'distal_inside_samples':distal_inside,
                        'distal_skin_min_gap_mm':min(distal_gaps,default=None),
                        'distal_skin_samples_within_2mm':sum(distance<=2 for distance in distal_gaps),'contact_regions':contact_regions}
    return result


def label_sample_joints(samples, weights):
    for family,items in samples.items():
        for row in items:
            source=[(row['vertex'],1)]if row['kind']=='vertex'else zip(row['source_vertices'],row['barycentric'])
            source=list(source)
            mass={j:sum(weights[i].get(f'RightHand{family}{j}',0)*w for i,w in source)for j in (1,2,3)}
            row['joint']=max(mass,key=mass.get)
    return samples


def label_index_contact_regions(samples,weights,rest_points,index_rest_inverse):
    """Separate the retained near-MCP palm blend without dropping its metrics."""
    for row in samples.get('Index',[]):
        source=[(row['vertex'],1)]if row['kind']=='vertex'else list(zip(row['source_vertices'],row['barycentric']))
        rest=sum((rest_points[i]*w for i,w in source),Vector())
        hand_mass=sum(weights[i].get('RightHand',0)*w for i,w in source)
        local_y=(index_rest_inverse@rest).y
        row['contact_region']='palmar_mcp_transition'if local_y<=.008 and hand_mass>=.15 else'moving_index_surface'
        row['hand_weight']=hand_mass
        row['index1_rest_y_mm']=local_y*1000
    return samples


def skin_edge_crossings(points,faces,regions,volume):
    """Actual skin-edge crossings of rendered triangles; works on open strips."""
    unique={tuple(sorted((a,b)))for face in faces for a,b in ((face[0],face[1]),(face[1],face[2]),(face[2],face[0]))}
    result={family:[]for family in regions}
    for a,b in unique:
        families=[family for family,ids in regions.items()if a in ids and b in ids]
        if not families:continue
        delta=points[b]-points[a];length=delta.length
        if length<1e-7:continue
        direction=delta/length
        hit,normal,index,distance=volume.bvh.ray_cast(points[a]+direction*1e-6,direction,max(0,length-2e-6))
        if hit is None:continue
        row={'vertices':[a,b],'hit_item_mm':list(hit*1000),'frame_triangle':index,
             'skin_edge_length_mm':length*1000,'hit_from_first_vertex_mm':(distance+1e-6)*1000}
        for family in families:result[family].append(row)
    return result


def override_curls(solver, candidate, splays=None):
    """Finger-only in-memory pose test; palm/index/thumb and source untouched."""
    for family,angles in candidate.items():
        for joint,angle in enumerate(angles,1):
            bone=solver.rig.pose.bones[f'RightHand{family}{joint}']
            location,_,scale=solver.base[bone.name].decompose()
            bone.location=location;bone.scale=scale
            bone.rotation_quaternion=Quaternion((1,0,0),-math.radians(angle))
        if splays and family in splays:
            bone=solver.rig.pose.bones[f'RightHand{family}1']
            bone.rotation_quaternion=Quaternion((0,0,1),math.radians(splays[family]))@bone.rotation_quaternion
    bpy.context.view_layer.update()


def _segment_triangle(p,q,a,b,c):
    """Strict crossing, excluding coplanar/tangent contact."""
    delta=q-p;normal=(b-a).cross(c-a);den=normal.dot(delta)
    if abs(den)<1e-12:return None
    t=normal.dot(a-p)/den
    margin=min(.001,1e-6/max(delta.length,1e-9))
    if not margin<t<1-margin:return None
    hit=p+delta*t;u=b-a;v=c-a;w=hit-a
    uu=u.dot(u);uv=u.dot(v);vv=v.dot(v);wu=w.dot(u);wv=w.dot(v)
    determinant=uu*vv-uv*uv
    if abs(determinant)<1e-20:return None
    s=(wu*vv-wv*uv)/determinant;r=(wv*uu-wu*uv)/determinant
    return hit if s>=-1e-7 and r>=-1e-7 and s+r<=1+1e-7 else None


def distal_self_contacts(points,faces,regions,weights,pairs=(('Middle','Ring'),('Ring','Pinky'))):
    """Direct distal surface intersections; shared proximal web is excluded."""
    subsets={};bvhs={}
    for family,indices in regions.items():
        ids={i for i in indices if sum(weights[i].get(f'RightHand{family}{j}',0)for j in (2,3))>.35}
        selected=[face for face in faces if all(i in ids for i in face)]
        subsets[family]=selected
        bvhs[family]=BVHTree.FromPolygons(points,selected,all_triangles=True)
    output={}
    for left,right in pairs:
        crossings=[]
        for i,j in bvhs[left].overlap(bvhs[right]):
            fa,fb=subsets[left][i],subsets[right][j]
            if set(fa)&set(fb):continue
            aa=[points[k]for k in fa];bb=[points[k]for k in fb];hits=[]
            for corners,other in ((aa,bb),(bb,aa)):
                for p,q in ((corners[0],corners[1]),(corners[1],corners[2]),(corners[2],corners[0])):
                    hit=_segment_triangle(p,q,*other)
                    if hit is not None and not any((hit-old).length<1e-6 for old in hits):hits.append(hit)
            if len(hits)<2:continue
            length=max((a-b).length for a in hits for b in hits)
            if length>.0001:crossings.append({'left_vertices':list(fa),'right_vertices':list(fb),
                                             'crossing_segment_mm':length*1000,'points_mm':[list(p*1000)for p in hits]})
        separations=[]
        for family,other in ((left,right),(right,left)):
            for face in subsets[family]:
                a,b,c=(points[k]for k in face)
                for p in (a,b,c,(a+b+c)/3,(a+b)/2,(b+c)/2,(c+a)/2):
                    nearest=bvhs[other].find_nearest(p)
                    if nearest[0]is not None:separations.append(nearest[3]*1000)
        output[f'{left}-{right}']={'distal_triangle_counts':[len(subsets[left]),len(subsets[right])],
            'strict_crossing_triangle_pairs':len(crossings),'maximum_crossing_segment_mm':max((r['crossing_segment_mm']for r in crossings),default=0),
            'sampled_surface_min_gap_mm':min(separations,default=None),'crossings':sorted(crossings,key=lambda r:r['crossing_segment_mm'],reverse=True)[:12]}
    return output
