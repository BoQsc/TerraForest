"""Measure actual evaluated sole support and solved arm/leg lengths per frame."""
from pathlib import Path
import sys,json,math
source=Path(__file__).resolve().with_name('author_behaviors.py')
sys.argv=[str(source),'--','--project',str(source.parent.parent)];__file__=str(source)
exec(compile(source.read_text().split("report={'input_sha256'")[0],str(source),'exec'))
from mathutils.bvhtree import BVHTree
report={'method':'Current procedural source evaluated through Blender armature skinning at each authored 60 Hz frame. Sole support uses upward exact triangle rays through the actual boot at the rung plane.',
        'author_script_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'base_source_blend_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'rung_height_m':.036,'rung_depth_m':.040,
        'rung_center_spacing_m':.30,'external_root_ascent_m_per_s':.30,'clips':{},'ladder_hand_support':[],'ladder_sole_support':[]}
for name,end,kind in NEW_CLIPS:
    rows=[];previous={};max_angles={};worst_leg=0.0;knee_min=180.0;knee_max=0.0
    for frame in range(end+1):
        pose(kind,frame,end)
        deps=bpy.context.evaluated_depsgraph_get()
        foot_bounds=[]
        for s,p,off in ((1,'Left',0),(-1,'Right',.5)):
            a=rig.pose.bones[p+'UpLeg'].head;b=rig.pose.bones[p+'Leg'].head;c=rig.pose.bones[p+'Foot'].head
            worst_leg=max(worst_leg,abs((b-a).length-length[p+'UpLeg']),abs((c-b).length-length[p+'Leg']))
            flex=math.degrees((b-a).angle(c-b));knee_min=min(knee_min,flex);knee_max=max(knee_max,flex)
            ob=bpy.data.objects['Z_Foot_'+('L' if s==1 else 'R')];ev=ob.evaluated_get(deps);mesh=ev.to_mesh();mesh.calc_loop_triangles()
            verts=[ev.matrix_world@v.co for v in mesh.vertices];tris=[tuple(t.vertices) for t in mesh.loop_triangles]
            foot_bounds.append(min(v.z for v in verts))
            if kind=='ladder':
                u=(frame/end+off)%1
                if u<.6:
                    target=Vector((s*.24,-.4,1.8-.6*u));wrist=rig.pose.bones[p+'Hand'].head
                    report['ladder_hand_support'].append({'frame':frame,'side':p,'wrist_error_m':(wrist-target).length,'target_local_m':list(target),'actual_local_m':list(wrist)})
                if u<.425:
                    center_local=.30-.6*u
                    origin=Vector((c.x,-.4,center_local-.30))
                    hit,normal,tri_index,distance=BVHTree.FromPolygons(verts,tris,all_triangles=True).ray_cast(origin,Vector((0,0,1)),1.0)
                    entry={'frame':frame,'side':p,'rung_world_center_m':center_local+frame/60*.30,'sole_sample_x_m':c.x,'sole_ray_hit':hit is not None}
                    if hit is not None:
                        entry.update({'sole_clearance_above_rung_top_m':hit.z-center_local-.018,'error_from_4mm_allowance_m':hit.z-center_local-.022,'sole_local_point_m':list(hit),'normal':list(normal)})
                    report['ladder_sole_support'].append(entry)
            ev.to_mesh_clear()
        for bone_name in ('LeftArm','LeftForeArm','RightArm','RightForeArm','LeftUpLeg','LeftLeg','RightUpLeg','RightLeg'):
            quat=rig.pose.bones[bone_name].matrix_basis.to_quaternion()
            if bone_name in previous:
                degrees=math.degrees(previous[bone_name].rotation_difference(quat).angle)
                if degrees>180:degrees=360-degrees
                if degrees>max_angles.get(bone_name,{}).get('degrees',0):max_angles[bone_name]={'frame':frame,'degrees':degrees}
            previous[bone_name]=quat.copy()
        rows.append({'frame':frame,'foot_min_z_m':foot_bounds})
    report['clips'][name]={'frames_inclusive':end+1,'maximum_leg_segment_length_error_m':worst_leg,'knee_flexion_degrees':[knee_min,knee_max],
                            'maximum_single_frame_local_rotation_degrees':max_angles,'minimum_boot_z_m':min(min(r['foot_min_z_m']) for r in rows),'foot_frames':rows}
    print('SUPPORT',name,report['clips'][name]['minimum_boot_z_m'],worst_leg,flush=True)
report['ladder_summary']={'hand_planted_samples':len(report['ladder_hand_support']),
 'maximum_wrist_error_m':max(r['wrist_error_m'] for r in report['ladder_hand_support']),
 'foot_planted_samples':len(report['ladder_sole_support']),
 'all_sole_rays_hit':all(r['sole_ray_hit'] for r in report['ladder_sole_support']),
 'maximum_sole_clearance_error_m':max(abs(r.get('error_from_4mm_allowance_m',999)) for r in report['ladder_sole_support']),
 'minimum_sole_rung_top_clearance_m':min(r.get('sole_clearance_above_rung_top_m',999) for r in report['ladder_sole_support'])}
export_record=source.with_name('behavior_authoring_report.json')
if export_record.exists():
    authored=json.loads(export_record.read_text())
    report['matches_exported_author_script']=authored.get('author_script_sha256')==report['author_script_sha256']
    report['exported_source_blend_sha256']=authored.get('output_blend_sha256')
    report['model_sha256']=authored.get('output_glb_sha256')
source.with_name('behavior_support_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('LADDER_SUPPORT',report['ladder_summary'],flush=True)
