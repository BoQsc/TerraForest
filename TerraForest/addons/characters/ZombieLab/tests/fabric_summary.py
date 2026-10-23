"""Summarize measured arm and cloth deformation, stdlib only. CC0-1.0.
Run fabric_probe.py in Blender first. This gate catches geometric failures;
it does not assign a physical fabric modulus or replace visual inspection.
"""
import argparse,hashlib,json,math
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);p.add_argument('--baseline',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args();r=json.loads(a.report.read_text());baseline=json.loads(a.baseline.read_text()) if a.baseline else None
expected={'Zombie_Idle':180,'Zombie_Walk':84,'Zombie_Attack':96,'Zombie_Hit':36}
contract_path=Path(__file__).resolve().parents[1]/'assets/Zombie.r4.behavior.json'
if contract_path.exists():
 contract=json.loads(contract_path.read_text())
 expected.update({name:int(spec['frames_inclusive'])-1 for name,spec in contract['actions'].items()})
expected_samples=sum(end*2+1 for end in expected.values())

def measured(report):
 out={'source_sha256':report['source_sha256'],'samples':report['sample_count'],'clips':{},'segments':report['rest_segments']};maxerr=0;minarea=(float('inf'),None);minwidth=(float('inf'),None);maxcenter=(0,None);degenerate=[];shaft_missing=[]
 for clip,c in report['clips'].items():
  rows=c['frames'];regions={};sections={}
  for region in rows[0]['regions']:
   values=[(f['frame'],f['regions'][region]) for f in rows]
   if not values[0][1]:continue
   def choose(metric,fn):
    frame,val=fn(values,key=lambda x:x[1][metric]);return {'value':val[metric],'frame':frame}
   regions[region]={'maximum_area_weighted_stretch_p95':choose('area_weighted_stretch_p95',max),'maximum_area_weighted_anisotropy_p95':choose('area_weighted_anisotropy_p95',max),'minimum_area_ratio':choose('area_ratio_min',min),'maximum_principal_stretch':choose('stretch_max',max),'minimum_principal_compression':choose('compression_min',min)}
  for section in report['rest_sections']:
   values=[(f['frame'],f['sections'][section]) for f in rows if f['sections'].get(section)]
   if not values:continue
   def choose(metric,fn):
    frame,val=fn(values,key=lambda x:x[1][metric]);return {'value':val[metric],'frame':frame}
   sections[section]={'minimum_area_ratio':choose('hull_area_m2_ratio',min),'minimum_width_ratio':choose('minimum_caliper_width_m_ratio',min),'maximum_center_from_rigid_reference_m':choose('section_center_from_rigid_reference_m',max)}
  for f in rows:
   for side,x in f['arm_lengths'].items():maxerr=max(maxerr,abs(x['upper_ratio_to_rest']-1),abs(x['forearm_ratio_to_rest']-1))
   if f['regular_cloth']['area_ratio_min']<.10:degenerate.append({'clip':clip,'frame':f['frame'],'minimum_regular_cloth_area_ratio':f['regular_cloth']['area_ratio_min']})
   for section in ['Z_UpperArm_L@0.6','Z_UpperArm_R@0.6','Z_Forearm_L@0.5','Z_Forearm_R@0.5']:
    m=f['sections'].get(section);loc={'clip':clip,'frame':f['frame'],'section':section}
    if not m:shaft_missing.append(loc);continue
    if m['hull_area_m2_ratio']<minarea[0]:minarea=(m['hull_area_m2_ratio'],loc)
    if m['minimum_caliper_width_m_ratio']<minwidth[0]:minwidth=(m['minimum_caliper_width_m_ratio'],loc)
    if m['section_center_from_rigid_reference_m']>maxcenter[0]:maxcenter=(m['section_center_from_rigid_reference_m'],loc)
  out['clips'][clip]={'samples':len(rows),'regions':regions,'sections':sections}
 out['maximum_arm_segment_relative_length_error']=maxerr;out['midshaft_minimum_area_ratio']={'value':minarea[0],**(minarea[1] or {})};out['midshaft_minimum_width_ratio']={'value':minwidth[0],**(minwidth[1] or {})};out['midshaft_maximum_center_error_m']={'value':maxcenter[0],**(maxcenter[1] or {})};out['near_degenerate_regular_cloth_samples']=degenerate;out['missing_midshaft_samples']=shaft_missing;return out
m=measured(r)
checks={'exact_frame_and_midpoint_coverage':r['step_frames']==.5 and r['sample_count']==expected_samples and set(r['clips'])==set(expected) and all([f['frame'] for f in r['clips'][clip]['frames']]==[i*.5 for i in range(end*2+1)] for clip,end in expected.items()),'arm_segments_keep_bind_length':m['maximum_arm_segment_relative_length_error']<=5e-5,'all_midshaft_sections_present':not m['missing_midshaft_samples'],'midshaft_area_retains_at_least_95_percent':m['midshaft_minimum_area_ratio']['value']>=.95,'midshaft_width_retains_at_least_95_percent':m['midshaft_minimum_width_ratio']['value']>=.95,'midshaft_center_within_5mm_of_rigid_segment':m['midshaft_maximum_center_error_m']['value']<=.005,'no_regular_cloth_faces_collapse_below_10_percent_rest_area':not m['near_degenerate_regular_cloth_samples']}
out={'source_sha256':r['source_sha256'],'measurement_file':a.report.name,'measurement_sha256':hashlib.sha256(a.report.read_bytes()).hexdigest(),'checks':checks,'passed':all(checks.values()),'threshold_basis':{'constant_lengths':'Skeletal segments have no intended scaling;5e-5 is a floating-point tolerance, not a proportion adjustment.','midshaft':'These sections lie away from intended short elbow/wrist/shoulder blend zones. Their geometry should behave almost as a rigid segment. A5% area/width loss or5mm centerline departure is an explicit collapse/curvature rejection.','cloth_degeneracy':'A regular face with at least2mm rest altitude that loses90% of its area is close to a line and cannot preserve its authored fabric patch. This is a catastrophic-collapse check, not a model of cloth elasticity.','strain':'Principal stretches and area-weighted percentiles are reported without an invented cotton/twill material limit. Long folds, construction seams and thin trim need visual interpretation.'},'current':m,'baseline':measured(baseline) if baseline else None,'limits':['Every integer frame and midpoint is measured; no claim is made for arbitrary unsampled times.','The cloth is a skinned game mesh, not a cloth simulation.','Cross-sectional hull areas describe silhouette and are not watertight anatomical volumes.','Passing these checks does not replace the separate exact intersection audit or visual frame inspection.']}
a.output.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({'passed':out['passed'],'checks':checks,'source_sha256':r['source_sha256'],'minimum_midshaft_area_ratio':m['midshaft_minimum_area_ratio'],'minimum_midshaft_width_ratio':m['midshaft_minimum_width_ratio'],'maximum_midshaft_center_error_m':m['midshaft_maximum_center_error_m'],'near_degenerate_regular_cloth_samples':len(m['near_degenerate_regular_cloth_samples'])},indent=2))
if not out['passed']:raise SystemExit(1)
