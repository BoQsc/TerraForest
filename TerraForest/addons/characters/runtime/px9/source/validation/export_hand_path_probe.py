# SPDX-License-Identifier: CC0-1.0
"""Read final GLB paths in Blender and compare with the current motion recipe.

Output supplies exact input positions for the matching native Godot audit.
Uses Blender mathutils and Python's standard library; no assets are modified.
"""
from pathlib import Path
import argparse,bisect,hashlib,json,math,sys
from mathutils import Matrix,Quaternion,Vector

HERE=Path(__file__).resolve().parent;sys.path.insert(0,str(HERE))
from joint_step_summary import GLB,sha,angle

def local_trs(node):
    if 'matrix' in node:
        m=Matrix([[node['matrix'][c*4+r] for c in range(4)] for r in range(4)])
        return tuple(m.decompose())
    q=node.get('rotation',(0,0,0,1))
    return Vector(node.get('translation',(0,0,0))),Quaternion((q[3],*q[:3])).normalized(),Vector(node.get('scale',(1,1,1)))

class PoseReader:
    def __init__(self,path):
        g=GLB(path);self.nodes=g.doc['nodes'];self.defaults=[local_trs(n) for n in self.nodes]
        self.parents={child:i for i,n in enumerate(self.nodes) for child in n.get('children',[])}
        self.names={n.get('name',str(i)):i for i,n in enumerate(self.nodes)};self.clips={}
        for a in g.doc['animations']:
            channels=[]
            for c in a['channels']:
                s=a['samplers'][c['sampler']];assert s.get('interpolation','LINEAR')=='LINEAR'
                channels.append((c['target']['node'],c['target']['path'],[v[0] for v in g.acc(s['input'])],g.acc(s['output'])))
            self.clips[a['name']]=channels
    def pose(self,clip,frame):
        trs=[[x.copy() for x in row] for row in self.defaults];t=frame/60
        for node,path,times,values in self.clips[clip]:
            stop=bisect.bisect_left(times,t)
            if stop==0:value=values[0]
            elif stop>=len(times):value=values[-1]
            elif abs(t-times[stop])<1e-8:value=values[stop]
            elif abs(t-times[stop-1])<1e-8:value=values[stop-1]
            else:
                weight=(t-times[stop-1])/(times[stop]-times[stop-1]);a,b=values[stop-1],values[stop]
                if path=='rotation':
                    # mathutils may use an unnormalised linear fallback for
                    # nearby quaternions. Normalise before matrix construction
                    # to preserve the glTF rotation semantics at subframes.
                    q=Quaternion((a[3],*a[:3])).normalized().slerp(Quaternion((b[3],*b[:3])).normalized(),weight).normalized();value=(q.x,q.y,q.z,q.w)
                else:value=tuple(x+(y-x)*weight for x,y in zip(a,b))
            if path=='rotation':trs[node][1]=Quaternion((value[3],*value[:3])).normalized()
            elif path=='translation':trs[node][0]=Vector(value)
            elif path=='scale':trs[node][2]=Vector(value)
        local=[Matrix.LocRotScale(*row) for row in trs];world={}
        def visit(i):
            if i not in world:world[i]=(visit(self.parents[i])@local[i] if i in self.parents else local[i])
            return world[i]
        for i in range(len(local)):visit(i)
        return {name:world[i] for name,i in self.names.items()}

def main():
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser=argparse.ArgumentParser();parser.add_argument('--package',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(argv);args.output.mkdir(parents=True,exist_ok=True);sys.path.insert(0,str(args.package/'source'))
    input_names=('Human.px9_eclipse.glb','Human.px9_eclipse.res','Human.r11.glb','item_px9.json','source/px9_motion.py','source/human_arm_solver.py','source/author_px9_first_person.py')
    input_hashes={n:sha(args.package/n) for n in input_names}
    import px9_motion as motion
    definition=json.loads((args.package/'item_px9.json').read_text());clip=next(c for c in definition['actions'] if c['id']=='rack')
    reader=PoseReader(args.package/'Human.px9_eclipse.glb')
    conversion=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
    samples=[]
    for quarter in range(clip['frame_end']*4+1):
        frame=quarter/4;world=reader.pose(clip['human_clip'],frame);expected=motion.evaluate('rack',frame)
        r={'frame':frame,'left_contact':expected['left_contact']}
        for side in ('left','right'):
            name=side.title()+'Hand';target=conversion@expected[side+'_world'];actual=world[name]
            r['expected_'+side+'_hand_translation_glb']=list(target.translation)
            r[side+'_hand_translation_glb']=list(actual.translation)
            r[side+'_hand_error_vs_continuous_recipe_metres']=(actual.translation-target.translation).length
            r[side+'_hand_rotation_error_degrees']=angle(actual.to_quaternion(),target.to_quaternion())
        r['bone_world_quaternions']={n:list(world[n].to_quaternion()) for n in ('LeftArm','LeftForeArm','LeftHand','RightHand')}
        samples.append(r)
    report={'schema':'px9-final-raw-glb-hand-path-audit-1','action':'rack','fps':60,'samples':samples,
        'source_hashes':input_hashes,
        'scope':'Every Rack quarter frame from 0 through 72, sampled from exported LINEAR quaternion channels and compared against the current continuous authored wrist targets.',
        'maximum_left_hand_error_metres':max(r['left_hand_error_vs_continuous_recipe_metres'] for r in samples),
        'maximum_right_hand_error_metres':max(r['right_hand_error_vs_continuous_recipe_metres'] for r in samples),
        'maximum_integer_left_hand_error_metres':max(r['left_hand_error_vs_continuous_recipe_metres'] for r in samples if r['frame'].is_integer()),
        'contact_revision':'Left slide contact 22..40 inclusive; release event remains 40.'}
    report['checks']={'289samples':len(samples)==289,'left_path_under1mm':report['maximum_left_hand_error_metres']<.001,'right_path_under1mm':report['maximum_right_hand_error_metres']<.001,'integer_left_under10micrometres':report['maximum_integer_left_hand_error_metres']<.00001,'inputs_stable_during_audit':input_hashes=={n:sha(args.package/n) for n in input_names}}
    report['passed']=all(report['checks'].values());path=args.output/'FINAL_RAW_GLB_HAND_PATH.json';path.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='samples'},indent=2),flush=True)
    assert report['passed'],report['checks']
if __name__=='__main__':main()
