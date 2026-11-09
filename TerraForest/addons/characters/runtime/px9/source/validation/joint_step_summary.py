# SPDX-License-Identifier: CC0-1.0
"""Per-frame local-joint continuity from the final Human animation GLB.

Python standard library only. No model, scene, rig or export is modified.
"""
from pathlib import Path
import argparse,csv,hashlib,json,math,re,struct

class GLB:
    def __init__(self,path):
        data=path.read_bytes();magic,version,total=struct.unpack_from('<4sII',data)
        assert magic==b'glTF' and version==2 and total==len(data)
        at=12;self.cache={}
        while at<len(data):
            length,kind=struct.unpack_from('<II',data,at);at+=8;chunk=data[at:at+length];at+=length
            if kind==0x4e4f534a:self.doc=json.loads(chunk)
            elif kind==0x004e4942:self.binary=chunk
    def acc(self,index):
        if index in self.cache:return self.cache[index]
        a=self.doc['accessors'][index];v=self.doc['bufferViews'][a['bufferView']]
        assert a['componentType']==5126 and not a.get('sparse')
        count={'SCALAR':1,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',count*4)
        values=[struct.unpack_from('<'+'f'*count,self.binary,offset+i*stride) for i in range(a['count'])]
        self.cache[index]=values;return values

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def angle(a,b):
    norm=math.sqrt(sum(x*x for x in a)*sum(x*x for x in b))
    dot=abs(sum(x*y for x,y in zip(a,b)))/norm
    return math.degrees(2*math.acos(min(1.,max(-1.,dot))))

def summarize(package):
    definition=json.loads((package/'item_px9.json').read_text())
    glb=GLB(package/'Human.px9_eclipse.glb')
    clips={a['name']:a for a in glb.doc['animations']}
    skeleton_nodes=set(n for skin in glb.doc.get('skins',[]) for n in skin['joints'])
    finger_pattern=re.compile(r'^(?:Left|Right)Hand(?:Thumb|Index|Middle|Ring|Pinky)[123]$')
    arm_pattern=re.compile(r'^(?:Left|Right)(?:Shoulder|Arm|ForeArm|Hand)$')
    rows=[];all_steps=[];loop_endpoints=[];sample_count=0
    for c in definition['actions']:
        a=clips[c['human_clip']];end=c['frame_end'];channels={}
        for ch in a['channels']:
            node=ch['target']['node']
            if ch['target']['path']!='rotation' or node not in skeleton_nodes:continue
            name=glb.doc['nodes'][node]['name'];assert name not in channels
            s=a['samplers'][ch['sampler']];assert s.get('interpolation','LINEAR')=='LINEAR'
            values,times=glb.acc(s['output']),glb.acc(s['input'])
            assert len(values)==len(times)==end+1,(c['id'],name,len(values),end)
            assert all(abs(t[0]*60-i)<.0001 for i,t in enumerate(times)),(c['id'],name,'times')
            channels[name]=values
        assert len(channels)==59,(c['id'],len(channels))
        for f in range(end+1):
            records=[]
            if f:
                for name,values in channels.items():
                    record={'action':c['id'],'from':f-1,'to':f,'bone':name,'degrees':angle(values[f-1],values[f]),
                            'finger':bool(finger_pattern.match(name)),'arm':bool(arm_pattern.match(name))}
                    records.append(record);all_steps.append(record)
            row={'action':c['id'],'frame':f,'seconds':f/60}
            for family,predicate in [('human',lambda r:True),('finger',lambda r:r['finger']),('arm',lambda r:r['arm'])]:
                matches=[r for r in records if predicate(r)];top=max(matches,key=lambda r:r['degrees']) if matches else None
                row[family+'_max_step_degrees']=top['degrees'] if top else None
                row[family+'_max_step_bone']=top['bone'] if top else None
            rows.append(row)
        if c['loop']:
            for name,values in channels.items():loop_endpoints.append({'action':c['id'],'bone':name,'degrees':angle(values[0],values[-1])})
        sample_count+=end+1
    summary={'schema':'px9-final-per-frame-joint-continuity-1','fps':60,'sample_count':sample_count,
        'clip_count':len(definition['actions']),'rotation_pairs_checked':len(all_steps),
        'definition':'Shortest local bone quaternion rotation between f-1 and f. Frame 0 has no preceding sample and its step/bone fields are null. Finger measurements include the 30 original thumb/finger joints.',
        'source_hashes':{n:sha(package/n) for n in ('Human.px9_eclipse.glb','item_px9.json')},
        'maximum_human_step':max(all_steps,key=lambda r:r['degrees']),
        'maximum_finger_step':max((r for r in all_steps if r['finger']),key=lambda r:r['degrees']),
        'maximum_arm_step':max((r for r in all_steps if r['arm']),key=lambda r:r['degrees']),
        'steps_above30degrees':[r for r in all_steps if r['degrees']>30],
        'steps_above45degrees':[r for r in all_steps if r['degrees']>45],
        'largest_finger_steps':sorted((r for r in all_steps if r['finger']),key=lambda r:r['degrees'],reverse=True)[:30],
        'maximum_loop_rotation_error':max(loop_endpoints,key=lambda r:r['degrees']),
        'rows':rows}
    assert sample_count==1582 and len(rows)==1582 and len(all_steps)==92158
    return summary

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--package',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    report=summarize(args.package)
    (args.output/'FINAL_PER_FRAME_JOINT_STEPS.json').write_text(json.dumps(report,indent=2)+'\n')
    with (args.output/'FINAL_PER_FRAME_JOINT_STEPS.csv').open('w',newline='',encoding='utf-8-sig') as f:
        writer=csv.DictWriter(f,fieldnames=list(report['rows'][0]));writer.writeheader();writer.writerows(report['rows'])
    print(json.dumps({k:v for k,v in report.items() if k not in ('rows','largest_finger_steps')},indent=2))
if __name__=='__main__':main()
