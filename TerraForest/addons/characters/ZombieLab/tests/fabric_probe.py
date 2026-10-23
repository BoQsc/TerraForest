"""Read-only triangle strain and arm shape measurements. Blender API + stdlib.
No material constants are inferred: skinning geometry is measured against bind rest.
"""
import argparse,bpy,hashlib,json,math,sys,time
from pathlib import Path
from mathutils import Vector
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--step',type=float,default=.5);parser.add_argument('--clips',nargs='*');args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pose_sampling import select_pose_action
scene=bpy.context.scene;rig=next(o for o in bpy.data.objects if o.type=='ARMATURE');started=time.time()
for t in rig.animation_data.nla_tracks:t.mute=True
objects=sorted([o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Z_') and not o.name.startswith('Z_Cap_')],key=lambda o:o.name)
tracked=[o for o in objects if o.name=='Z_Torso' or any(k in o.name for k in ['UpperArm','Forearm','Thigh','Shin'])]
rest_positions={o.name:[o.matrix_world@v.co for v in o.data.vertices] for o in tracked}
triangles={}; metrics={}; weights={}
for o in tracked:
 o.data.calc_loop_triangles();rows=[]
 for i,t in enumerate(o.data.loop_triangles):
  mat=o.data.materials[t.material_index].name
  if not mat.startswith('Zombie.Cloth.') and not ('Arm' in o.name or 'Forearm' in o.name):continue
  a,b,c=[rest_positions[o.name][j] for j in t.vertices];e1=b-a;e2=c-a;l=e1.length;proj=e2.dot(e1)/l if l else 0.;h2=e2.length_squared-proj*proj;h=math.sqrt(max(0.,h2))
  if l*h<1e-12:continue
  rows.append({'index':i,'indices':list(t.vertices),'material':mat,'l':l,'proj':proj,'h':h,'area':l*h*.5,'rest_min_altitude':l*h/max(l,e2.length,(c-b).length),'region':o.name+' / '+mat})
 triangles[o.name]=rows
 weights[o.name]=[{o.vertex_groups[g.group].name:g.weight for g in v.groups} for v in o.data.vertices]

def weighted_percentile(values,p):
 values=sorted(values);total=sum(w for v,w in values);threshold=p*total;acc=0.
 for v,w in values:
  acc+=w
  if acc>=threshold:return v
 return values[-1][0] if values else None

def summarized(rows):
 area=sum(r['area'] for r in rows)
 if not area:return {}
 return {'triangles':len(rows),'rest_area_m2':area,'stretch_max':max(r['stretch'] for r in rows),'compression_min':min(r['compression'] for r in rows),'anisotropy_max':max(r['anisotropy'] for r in rows),'area_ratio_min':min(r['area_ratio'] for r in rows),'area_ratio_max':max(r['area_ratio'] for r in rows),'area_weighted_stretch_p95':weighted_percentile([(r['stretch'],r['area']) for r in rows],.95),'area_weighted_compression_p05':weighted_percentile([(r['compression'],r['area']) for r in rows],.05),'area_weighted_anisotropy_p95':weighted_percentile([(r['anisotropy'],r['area']) for r in rows],.95),'rest_area_fraction_stretched_over_1p25':sum(r['area'] for r in rows if r['stretch']>1.25)/area,'rest_area_fraction_compressed_under_0p65':sum(r['area'] for r in rows if r['compression']<.65)/area,'rest_area_fraction_anisotropy_over_2':sum(r['area'] for r in rows if r['anisotropy']>2)/area}

def section_measure(verts,trs,origin,axis):
 # Surface/plane intersections give an objective cross-sectional hull; all skin
 # surfaces are included. It measures loss of outer silhouette, not soft volume.
 axis=axis.normalized();basis=axis.orthogonal().normalized();other=axis.cross(basis).normalized();points=[]
 for tri in trs:
  if not tri['material'].startswith('Zombie.Body.'):continue
  xyz=[verts[j] for j in tri['indices']];d=[(v-origin).dot(axis) for v in xyz]
  if min(d)>0 or max(d)<0:continue
  for i in range(3):
   j=(i+1)%3
   if d[i]*d[j]<0:
    p=xyz[i]+(xyz[j]-xyz[i])*(d[i]/(d[i]-d[j]))-origin;points.append((p.dot(basis),p.dot(other)))
 if len(points)<3:return None
 points=sorted(set(points));hull=[]
 def cross(o,a,b):return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
 for p in points:
  while len(hull)>=2 and cross(hull[-2],hull[-1],p)<=0:hull.pop()
  hull.append(p)
 lower=len(hull)
 for p in reversed(points[:-1]):
  while len(hull)>lower and cross(hull[-2],hull[-1],p)<=0:hull.pop()
  hull.append(p)
 hull=hull[:-1];crosses=[hull[i][0]*hull[(i+1)%len(hull)][1]-hull[(i+1)%len(hull)][0]*hull[i][1] for i in range(len(hull))];signed_twice_area=sum(crosses);area=abs(signed_twice_area)*.5
 if area<1e-12:return None
 # Area centroid is invariant to inserted/removed collinear hull samples.
 cx=sum((hull[i][0]+hull[(i+1)%len(hull)][0])*crosses[i] for i in range(len(hull)))/(3*signed_twice_area);cy=sum((hull[i][1]+hull[(i+1)%len(hull)][1])*crosses[i] for i in range(len(hull)))/(3*signed_twice_area)
 # Smallest and largest caliper widths of the convex section, rotation invariant.
 widths=[]
 for i,p in enumerate(hull):
  q=hull[(i+1)%len(hull)];dx=q[0]-p[0];dy=q[1]-p[1];length=math.hypot(dx,dy)
  if length<1e-10:continue
  distances=[(v[0]*(-dy)+v[1]*dx)/length for v in hull];widths.append(max(distances)-min(distances))
 return {'hull_area_m2':area,'minimum_caliper_width_m':min(widths),'maximum_caliper_width_m':max(widths),'plane_hits':len(points),'center_blender_m':list(origin+basis*cx+other*cy)} if widths else None

rest_sections={}
for prefix,suffix in [('Left','L'),('Right','R')]:
 for segment,bone_name,t_values in [('UpperArm',prefix+'Arm',[.60,.82]),('Forearm',prefix+'ForeArm',[.18,.5,.82])]:
  name='Z_'+segment+'_'+suffix;bone=rig.data.bones[bone_name];axis=bone.tail_local-bone.head_local
  for t in t_values:
   key=name+'@'+str(t);r=section_measure(rest_positions[name],triangles[name],bone.head_local+axis*t,axis)
   rest_sections[key]={'bone':bone_name,'t':t,'object':name,'rest':r}
report={'source':bpy.data.filepath,'source_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),'fps':scene.render.fps,'step_frames':args.step,'basis':'Triangle principal stretch factors from bind-rest tangent metric; area-weighted percentiles; planar skin silhouette sections centered on each bone.','limits':['Measurements describe LBS geometry, not simulated cloth material stress.','A compression factor below one may be a legitimate fold. Large regions stretched above rest cannot represent an inextensible fabric without compensation.','Tiny existing seam/trim triangles are reported separately from area-weighted values so isolated slivers cannot dominate the diagnosis.','Cross-sections use a convex skin hull and may bridge open wounds; they are a silhouette diagnostic, not watertight enclosed volume.','No artistic pass is inferred from absence of triangle intersections.'],'regular_triangle_definition':'Rest minimum altitude at least2mm; smaller trim/UV slivers remain in raw extrema but cannot alone decide a broadfabric-collapse gate.','rest_segments':{prefix:{'upper_arm_m':rig.data.bones[prefix+'Arm'].length,'forearm_m':rig.data.bones[prefix+'ForeArm'].length,'forearm_upper_ratio':rig.data.bones[prefix+'ForeArm'].length/rig.data.bones[prefix+'Arm'].length} for prefix in ['Left','Right']},'rest_sections':rest_sections,'clips':{}}
for action in sorted([a for a in bpy.data.actions if a.name.startswith('Zombie_') and (not args.clips or a.name in args.clips)],key=lambda a:a.name):
 select_pose_action(rig,action)
 start,end=action.frame_range;count=int(round((end-start)/args.step))+1;frames=[];clip_worst=[]
 for sample in range(count):
  frame=start+sample*args.step;scene.frame_set(math.floor(frame),subframe=frame%1);bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();frame_rows=[];regions={};posed={}
  for o in tracked:
   ev=o.evaluated_get(deps);mesh=ev.to_mesh();verts=[ev.matrix_world@v.co for v in mesh.vertices];ev.to_mesh_clear();posed[o.name]=verts
   for t in triangles[o.name]:
    a,b,c=[verts[i] for i in t['indices']];e1=b-a;e2=c-a;u=e1/t['l'];v=(e2-e1*(t['proj']/t['l']))/t['h'];g00=u.dot(u);g11=v.dot(v);g01=u.dot(v);disc=math.sqrt(max(0.,(g00-g11)**2+4*g01*g01));smax=math.sqrt(max(0.,(g00+g11+disc)*.5));smin=math.sqrt(max(0.,(g00+g11-disc)*.5));row={'triangle':t['index'],'indices':t['indices'],'object':o.name,'material':t['material'],'area':t['area'],'rest_min_altitude_m':t['rest_min_altitude'],'stretch':smax,'compression':smin,'anisotropy':smax/max(smin,1e-10),'area_ratio':smax*smin,'frame':frame};frame_rows.append(row);regions.setdefault(t['region'],[]).append(row)
  sections={}
  for key,s in rest_sections.items():
   pb=rig.pose.bones[s['bone']];axis=pb.tail-pb.head;val=section_measure(posed[s['object']],triangles[s['object']],pb.head+axis*s['t'],axis)
   if val and s['rest']:
    for metric in ['hull_area_m2','minimum_caliper_width_m','maximum_caliper_width_m']:val[metric+'_ratio']=val[metric]/s['rest'][metric]
    expected=rig.pose.bones[s['bone']].matrix@rig.data.bones[s['bone']].matrix_local.inverted()@Vector(s['rest']['center_blender_m']);val['section_center_from_rigid_reference_m']=(Vector(val['center_blender_m'])-expected).length
   sections[key]=val
  cloth=[r for r in frame_rows if r['material'].startswith('Zombie.Cloth.')];skin=[r for r in frame_rows if r['material'].startswith('Zombie.Body.')]
  robust=[r for r in frame_rows if r['rest_min_altitude_m']>=.002 and r['material'].startswith('Zombie.Cloth.')]
  worst=sorted(robust,key=lambda r:r['anisotropy'],reverse=True)[:4];clip_worst.extend(worst)
  arm_lengths={}
  for prefix in ['Left','Right']:
   upper=rig.pose.bones[prefix+'Arm'];fore=rig.pose.bones[prefix+'ForeArm'];hand=rig.pose.bones[prefix+'Hand'];l1=(fore.head-upper.head).length;l2=(hand.head-fore.head).length
   arm_lengths[prefix]={'upper_arm_m':l1,'forearm_m':l2,'upper_ratio_to_rest':l1/rig.data.bones[prefix+'Arm'].length,'forearm_ratio_to_rest':l2/rig.data.bones[prefix+'ForeArm'].length}
  frames.append({'frame':frame,'cloth':summarized(cloth),'arm_skin':summarized(skin),'regular_cloth':summarized(robust),'arm_lengths':arm_lengths,'regions':{k:summarized(rs) for k,rs in regions.items()},'sections':sections,'worst_regular_cloth_triangles':worst})
 worst=sorted(clip_worst,key=lambda r:r['anisotropy'],reverse=True)[:20]
 for r in worst:r['rest_vertices']=[list(rest_positions[r['object']][i]) for i in r['indices']];r['weights']=[weights[r['object']][i] for i in r['indices']]
 report['clips'][action.name]={'sample_count':len(frames),'frames':frames,'worst_regular_cloth_triangles':worst}
 print('CLIP',action.name,len(frames),'worst',[(r['frame'],r['object'],r['triangle'],round(r['stretch'],3),round(r['compression'],3),round(r['anisotropy'],3)) for r in worst[:4]],flush=True)
report['elapsed_seconds']=time.time()-started;report['sample_count']=sum(c['sample_count'] for c in report['clips'].values());args.output.write_text(json.dumps(report,indent=2)+'\n');print('FABRIC_PROBE',args.output,'samples',report['sample_count'],'seconds',report['elapsed_seconds'],flush=True)
