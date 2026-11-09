# SPDX-License-Identifier: CC0-1.0
"""Read-only native contact review of actual saved integer-frame actions.

Open the saved .blend with Blender, then pass --manifest and --report.
No authoring function or pose override is called. Geometry is evaluated from
the saved skin and saved human/weapon actions. Uses native Blender and stdlib.
"""
import bpy,json,sys,math,hashlib,argparse
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from contact_probe import MeshVolume,evaluated_mesh,finger_regions,surface_samples,label_sample_joints,label_index_contact_regions,summarize_samples,distal_self_contacts,skin_edge_crossings
parser=argparse.ArgumentParser()
parser.add_argument('--manifest',required=True,type=Path)
parser.add_argument('--report',required=True,type=Path)
parser.add_argument('--all-frames',action='store_true')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]if'--'in sys.argv else[])
definition=json.loads(args.manifest.read_text())
source=Path(bpy.data.filepath)
if not source.is_file():raise ValueError('Open the saved Blender source before running this audit.')
scene=bpy.context.scene;human=bpy.data.objects['Human_Rig'];item=bpy.data.objects['WeaponSkeleton'];variant=bpy.data.objects['Human_FP_Hands']
human.animation_data.use_nla=False;item.animation_data.use_nla=False
regions,weights=finger_regions(variant,('Thumb','Index','Middle','Ring','Pinky'))
selected={
 'reload_empty':list(range(18,27))+list(range(30,66))+list(range(138,153))+[98,112],
 'fire':list(range(25)), 'idle':[0,60], 'aim_idle':[0,60],
 'inspect':[0,57,140,240], 'rack':[18,35,47],
}
hand_inverse=human.data.bones['RightHand'].matrix_local.inverted()
index_rest_inverse=human.data.bones['RightHandIndex1'].matrix_local.inverted()
rest_points=[v.co.copy()for v in variant.data.vertices]
palm_ids={'Heel':[],'CentralPalm':[]}
for vertex in variant.data.vertices:
    if sum(w for n,w in weights[vertex.index].items()if n.startswith('RightHand'))<.5:continue
    p=hand_inverse@vertex.co
    if -.035<p.x<.045 and p.z<-.010:
        if .025<p.y<.060:palm_ids['Heel'].append(vertex.index)
        elif .060<=p.y<.100:palm_ids['CentralPalm'].append(vertex.index)
report={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'mode':'all saved integer frames'if args.all_frames else'selected saved integer frames including reload_empty18..26,30..65,138..152',
        'measurement':'actual saved deformed skin in evaluated weapon-object space',
        'limits':['Closed-solid ray parity is separate from the labeled outer-grip span envelope.','Open frontstrap strips do not support watertight inside classification.','Finite triangle sampling cannot prove zero triangle-volume intersection.','Distal finger self-contact excludes shared proximal web and tangent/coplanar contact.'],
        'index_contact_region_definition':'palmar_mcp_transition: rest-space RightHandIndex1 localY<=8mm and interpolated RightHand weight>=0.15. These samples remain in whole-Index contact maxima. All other Index samples are moving_index_surface.',
        'frames':[],'actions':{},'frame_surface_invariance_max_mm':0}

def auxiliary_contact(samples,inverse):
    """Actual additional weapon surfaces; no envelope claim for these parts."""
    parts=('GripPanel_Left','GripPanel_Right','MagazineBase','Slide','SlideStop','MagazineRelease','Trigger')
    points=[];faces=[];owners=[];targets={}
    for name in parts:
        p,f=evaluated_mesh(bpy.data.objects[name],inverse);offset=len(points)
        points.extend(p);faces.extend(tuple(offset+i for i in face)for face in f);owners.extend([name]*len(f))
        if name in('SlideStop','MagazineRelease','Trigger'):targets[name]=BVHTree.FromPolygons(p,f,all_triangles=True)
    auxiliary=MeshVolume(points,faces,'Grip plates floorplate slide and controls')
    output={}
    for family,rows in samples.items():
        inside=[];unknown=0;nearest=[];contact_regions={}
        for row in rows:
            found=auxiliary.probe(row['point'],3)
            nearest.append(found['nearest_distance_mm'])
            if 'contact_region'in row:
                contact_regions.setdefault(row['contact_region'],0)
                if found['inside']is True:contact_regions[row['contact_region']]=max(contact_regions[row['contact_region']],found['nearest_distance_mm'])
            if found['inside']is True:
                inside.append({**{k:v for k,v in row.items()if k!='point'},**found,
                               'part':owners[found['nearest_face']], 'point_mm':list(row['point']*1000)})
            elif found['inside']is None:unknown+=1
        output[family]={'inside_samples':len(inside),'unknown_samples':unknown,
                        'maximum_closed_depth_mm':max((r['nearest_distance_mm']for r in inside),default=0),
                        'minimum_unsigned_distance_mm':min(nearest,default=None),
                        'deepest':sorted(inside,key=lambda r:r['nearest_distance_mm'],reverse=True)[:12],'contact_region_closed_max_mm':contact_regions}
    distances={name:min((target.find_nearest(row['point'])[3]*1000 for row in samples['Thumb']if row.get('joint')==3),default=None)for name,target in targets.items()if name!='Trigger'}
    trigger_distance=min((targets['Trigger'].find_nearest(row['point'])[3]*1000 for row in samples['Index']if row.get('joint')==3),default=None)
    return output,auxiliary.topology,distances,trigger_distance

volume=None;reference_frame_points=None;reference_skin=None
for action in definition['actions']:
    name=action['id']
    frames=range(int(action['frame_end'])+1)if args.all_frames else sorted(set(f for f in selected.get(name,[])if f<=action['frame_end']))
    if not frames:continue
    human.animation_data.action=bpy.data.actions[action['human_action']]
    item.animation_data.action=bpy.data.actions[action['weapon_action']]
    count=0
    for frame in frames:
        scene.frame_set(frame);bpy.context.view_layer.update()
        graph=bpy.context.evaluated_depsgraph_get();inverse=item.evaluated_get(graph).matrix_world.inverted()
        frame_points,frame_faces=evaluated_mesh(bpy.data.objects['Frame'],inverse)
        if volume is None:
            volume=MeshVolume(frame_points,frame_faces);reference_frame_points=frame_points
            report['frame_topology']=volume.topology
        delta=max((a-b).length*1000 for a,b in zip(frame_points,reference_frame_points))
        report['frame_surface_invariance_max_mm']=max(report['frame_surface_invariance_max_mm'],delta)
        if delta>.01:raise ValueError(f'Frame local geometry changed by{delta}mm at{name}{frame}; rebuild volume per frame.')
        points,faces=evaluated_mesh(variant,inverse)
        samples=label_sample_joints(surface_samples(points,faces,regions,'dense'),weights)
        label_index_contact_regions(samples,weights,rest_points,index_rest_inverse)
        metrics=summarize_samples(samples,volume,3)
        auxiliary_samples={**samples,**{region:[{'kind':'vertex','vertex':i,'point':points[i]}for i in ids]for region,ids in palm_ids.items()}}
        auxiliary,auxiliary_topology,control_distances,trigger_distance=auxiliary_contact(auxiliary_samples,inverse)
        if 'auxiliary_topology'not in report:report['auxiliary_topology']=auxiliary_topology
        self_contact=distal_self_contacts(points,faces,regions,weights,pairs=(('Index','Middle'),('Middle','Ring'),('Ring','Pinky')))
        palm={}
        for region,ids in palm_ids.items():
            findings=[{'vertex':i,**volume.probe(points[i],3),'point_mm':list(points[i]*1000),
                       'dominant_bone':max(weights[i],key=weights[i].get),'dominant_weight':max(weights[i].values())}for i in ids]
            inside=[r for r in findings if r['inside']is True]
            outside=[r['nearest_distance_mm']for r in findings if r['inside']is False]
            palm[region]={'vertices':len(ids),'inside_vertices':len(inside),'maximum_closed_depth_mm':max((r['nearest_distance_mm']for r in inside),default=0),'minimum_outside_gap_mm':min(outside,default=None),'deepest':sorted(inside,key=lambda r:r['nearest_distance_mm'],reverse=True)[:6]}
        row={'action':name,'frame':frame,'metrics':metrics,'auxiliary_contact':auxiliary,'thumb_distal_control_surface_distance_mm':control_distances,'index_distal_trigger_surface_distance_mm':trigger_distance,'palm_contact':palm,'finger_self_contact':self_contact,
             'weapon_crossing_edges':skin_edge_crossings(points,faces,regions,volume)}
        report['frames'].append(row);count+=1
        if count%8==0:
            print('CONTACT_FRAMES',name,count,'through_frame',frame,flush=True)
            args.report.write_text(json.dumps(report,indent=2)+'\n')
    report['actions'][name]=count
    print('CONTACT_ACTION',name,count,'maxclosed',{f:max(r['metrics'][f]['max_inside_distance_mm']for r in report['frames']if r['action']==name)for f in regions},flush=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
report['summary']={
 'evaluated_frames':len(report['frames']),
 'finger_closed_max_mm':{f:max(r['metrics'][f]['max_inside_distance_mm']for r in report['frames'])for f in regions},
 'finger_outer_span_max_mm':{f:max(r['metrics'][f]['outer_grip_max_orthogonal_exit_mm']for r in report['frames'])for f in regions},
 'auxiliary_weapon_parts_closed_max_mm':{f:max(r['auxiliary_contact'][f]['maximum_closed_depth_mm']for r in report['frames'])for f in (*regions,*palm_ids)},
 'distal_crossing_pairs_max':{pair:max(r['finger_self_contact'][pair]['strict_crossing_triangle_pairs']for r in report['frames'])for pair in ('Index-Middle','Middle-Ring','Ring-Pinky')},
 'index_contact_regions_closed_max_mm':{region:max(max(r['metrics']['Index']['contact_regions'].get(region,{}).get('closed_max_mm',0),r['auxiliary_contact']['Index']['contact_region_closed_max_mm'].get(region,0))for r in report['frames'])for region in('moving_index_surface','palmar_mcp_transition')},
 'palm_closed_max_mm':{p:max(r['palm_contact'][p]['maximum_closed_depth_mm']for r in report['frames'])for p in palm_ids},
}
args.report.write_text(json.dumps(report,indent=2)+'\n')
print('CONTACT_SUMMARY',json.dumps(report['summary']),flush=True)
