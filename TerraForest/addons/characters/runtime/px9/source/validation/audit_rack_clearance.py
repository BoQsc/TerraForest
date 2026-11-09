# SPDX-License-Identifier: CC0-1.0
"""Compare actual saved Rack Actions and evaluated left-hand skin.

Run inside Blender with only Blender-native bpy/mathutils and the Python
standard library. The sibling contact_probe.py supplies the closed-component
ray-parity classifier. Neither input .blend is saved or changed.

Example:
blender -b --factory-startup --python audit_rack_clearance.py -- \
  --baseline /path/to/previous.blend --candidate /path/to/current.blend \
  --report /path/to/RACK_CLEARANCE_SAVED.json
"""
from pathlib import Path
import argparse,hashlib,json,math,sys
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from contact_probe import MeshVolume,evaluated_mesh,surface_samples

FAMILIES=('Thumb','Index','Middle','Ring','Pinky','Palm')
PARTS=('Slide','Frame','Barrel','FrontSight','RearSight','SlideStop','MuzzleHousing')
DENSE_FRAMES=(22,31,40,44)

def regions_for(body):
    regions={f:set()for f in FAMILIES};weights=[]
    for vertex in body.data.vertices:
        row={body.vertex_groups[g.group].name:float(g.weight)for g in vertex.groups};weights.append(row)
        masses={f:sum(value for name,value in row.items()if name.startswith('LeftHand'+f))for f in FAMILIES if f!='Palm'}
        family=max(masses,key=masses.get)
        if masses[family]>=.45:regions[family].add(vertex.index)
        elif row.get('LeftHand',0)>=.4:regions['Palm'].add(vertex.index)
    return regions,weights

def sample_weights(sample,weights):
    source=[(sample['vertex'],1)]if sample['kind']=='vertex'else zip(sample['source_vertices'],sample['barycentric'])
    row={}
    for i,w in source:
        for name,value in weights[i].items():row[name]=row.get(name,0)+value*w
    return dict(sorted(row.items(),key=lambda pair:-pair[1])[:6])

def frame_metrics(scene,human,item,body,frame,regions,weights,mode,topology):
    whole=math.floor(frame)
    scene.frame_set(whole,subframe=frame-whole);bpy.context.view_layer.update()
    inverse=item.evaluated_get(bpy.context.evaluated_depsgraph_get()).matrix_world.inverted()
    points,faces=evaluated_mesh(body,inverse)
    samples=surface_samples(points,faces,regions,mode)
    result={'frame':frame,'sampling':mode,'parts':{}}
    for name in PARTS:
        pp,ff=evaluated_mesh(bpy.data.objects[name],inverse)
        volume=MeshVolume(pp,ff,name)
        if name not in topology:topology[name]=volume.topology
        part={}
        for family,rows in samples.items():
            inside=[];unknown=0;disagreement=0;nearest=math.inf
            for sample in rows:
                found=volume.probe(sample['point'],3)
                nearest=min(nearest,found['nearest_distance_mm'])
                disagreement+=bool(found['ray_disagreement'])
                if found['inside']is None:unknown+=1
                elif found['inside']is True:
                    inside.append({**{k:v for k,v in sample.items()if k!='point'},
                        'depth_mm':found['nearest_distance_mm'],
                        'point_item_mm':list(sample['point']*1000),
                        'nearest_point_item_mm':found['nearest_point_mm'],
                        'inside_components':found['inside_components'],
                        'weights':sample_weights(sample,weights)})
            inside.sort(key=lambda row:row['depth_mm'],reverse=True)
            part[family]={'samples':len(rows),'inside_samples':len(inside),'unknown_samples':unknown,
                'ray_disagreement_samples':disagreement,
                'maximum_closed_depth_mm':inside[0]['depth_mm']if inside else 0,
                'depth_sum_mm':sum(row['depth_mm']for row in inside),
                'minimum_unsigned_surface_distance_mm':nearest,
                'deepest':inside[:3]}
        result['parts'][name]=part
    return result

def inspect_source(source,label,write_progress):
    bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False)
    scene=bpy.context.scene;human=bpy.data.objects['Human_Rig'];item=bpy.data.objects['WeaponSkeleton'];body=bpy.data.objects['Human_FP_Hands']
    human.animation_data.use_nla=False;item.animation_data.use_nla=False
    human.animation_data.action=bpy.data.actions['FP_PX9_ECLIPSE_Rack']
    item.animation_data.action=bpy.data.actions['PX9_FP__Rack']
    regions,weights=regions_for(body)
    result={'source_name':source.name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'human_action':human.animation_data.action.name,'weapon_action':item.animation_data.action.name,
        'sampling':'73 integer frames with vertices, triangle centroids and edge midpoints; dense surface resampling at22,31,40,44',
        'region_vertices':{f:len(ids)for f,ids in regions.items()},'parts_topology':{},'frames':[],'dense_frames':[]}
    for frame in range(73):
        result['frames'].append(frame_metrics(scene,human,item,body,frame,regions,weights,'coarse',result['parts_topology']))
        if frame%6==0:
            print('RACK_SAVED_AUDIT',label,frame,'of72',flush=True)
            write_progress(result)
    for frame in DENSE_FRAMES:
        result['dense_frames'].append(frame_metrics(scene,human,item,body,frame,regions,weights,'dense',result['parts_topology']))
        print('RACK_SAVED_DENSE',label,frame,flush=True)
        write_progress(result)
    return result

def summarize_pair(before,after):
    changes=[];deep_regressions=[];improvements=[]
    for old,new in zip(before['frames'],after['frames']):
        assert old['frame']==new['frame']
        for part in PARTS:
            for family in FAMILIES:
                a=old['parts'][part][family]['maximum_closed_depth_mm'];b=new['parts'][part][family]['maximum_closed_depth_mm']
                row={'frame':old['frame'],'part':part,'family':family,'before_mm':a,'after_mm':b,'delta_mm':b-a}
                if abs(b-a)>.1:changes.append(row)
                if b-a>4:deep_regressions.append(row)
                if a-b>4:improvements.append(row)
    deep_regressions.sort(key=lambda row:-row['delta_mm'])
    improvements.sort(key=lambda row:row['delta_mm'])
    dense_old=next(r for r in before['dense_frames']if r['frame']==31)
    dense_new=next(r for r in after['dense_frames']if r['frame']==31)
    return {'matched_integer_frames':73,'matched_dense_frames':list(DENSE_FRAMES),
        'frame31_dense':{part:{family:{'before_mm':dense_old['parts'][part][family]['maximum_closed_depth_mm'],
                                    'after_mm':dense_new['parts'][part][family]['maximum_closed_depth_mm'],
                                    'after_unsigned_gap_mm':dense_new['parts'][part][family]['minimum_unsigned_surface_distance_mm']}
                                  for family in FAMILIES}for part in PARTS},
        'per_region_depth_changes_over_0_1mm':changes,
        'increases_over_4mm':deep_regressions,'reductions_over_4mm':improvements,
        'interpretation':[
            'The requested compact Rack grasp is a visual finding; sampled volume depth alone does not establish appearance or pressure/contact fitting.',
            'Read the actual per-frame and dense results for this saved revision. No zero-overlap conclusion is hard-coded.',
            'The unchanged support pose can contain hidden crossings. Compare every named region rather than relying only on an aggregate worst depth.',
            'The Blender Action and evaluated optional skin are sampled without authoring overrides. Numerical coverage is separate from visual coverage.']}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--baseline',type=Path,required=True)
    parser.add_argument('--candidate',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]if'--'in sys.argv else[])
    args.report.parent.mkdir(parents=True,exist_ok=True)
    report={'schema':'px9-rack-saved-surface-review/v1','measurement':'evaluated saved skinned left-hand surface in evaluated item-object metres, displayed as millimetres',
      'scope':'Rack only; frame0..72 inclusive at60FPS; no authoring pose functions or candidate overrides are used',
      'limits':['Finite surface samples cannot prove zero triangle-volume overlap.','Inside tests use3-ray parity only for closed welded components. Open components are unknown, not silently clear.','These are numerical checks, not73 manual visual inspections.','Near-surface gaps are unsigned and are not pressure measurements.','The3D body and weapon are fictional game meshes; these checks do not validate mechanical operation.'],
      'baseline':{},'candidate':{},'complete':False}
    def progress(label):
        def write(result):
            report[label]=result;args.report.write_text(json.dumps(report,indent=2)+'\n')
        return write
    report['baseline']=inspect_source(args.baseline,'baseline',progress('baseline'))
    report['candidate']=inspect_source(args.candidate,'candidate',progress('candidate'))
    report['comparison']=summarize_pair(report['baseline'],report['candidate'])
    report['complete']=True
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print('RACK_SAVED_AUDIT_COMPLETE',json.dumps({'integer_frames_per_source':73,'dense_frames':list(DENSE_FRAMES),'frame31':report['comparison']['frame31_dense'],'increases_over4mm':len(report['comparison']['increases_over_4mm'])}),flush=True)
if __name__=='__main__':main()
