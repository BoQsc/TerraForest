# SPDX-License-Identifier: 0BSD
"""Read the frozen visual diagnostic state; never mutate a gameplay save."""
import collections,json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
data=(ROOT/'reports/water_repeated_mining.bin').read_bytes()
magic,version,catalog,count=struct.unpack_from('<4I',data)
assert magic==0x31575256 and version>=2
cells={}
for region in range(count):
 offset=32+catalog+region*9076
 key,valid,has_density=struct.unpack_from('<QII',data,offset)
 if not valid:continue
 rx,ry,rz=(key>>24)&4095,(key>>12)&4095,key&4095
 for i in range(512):
  floor,ceiling,amount=struct.unpack_from('<HHQ',data,offset+16+i*12)
  cells[(rx*8+i%8,ry*8+(i//8)%8,rz*8+i//64)]=(floor,ceiling,amount&0x7fffffffffffffff)
def surface(p):
 if p not in cells:return None
 f,c,v=cells[p]
 if not v or f==c:return None
 top=p[1]*.5+f*.001+min(v,(c-f)*250)/250000
 above=cells.get((p[0],p[1]+1,p[2]))
 if top>=(p[1]+1)*.5-.00001 and above and above[0]==0 and above[2]:return None
 return top
def joined(a,b):
 if a not in cells or b not in cells:return False
 af,ac,av=cells[a];bf,bc,bv=cells[b];opening=max(af,bf)
 return opening<min(ac,bc) and af*250+av>opening*250 and bf*250+bv>opening*250
stats=collections.Counter();examples=[]
for p in cells:
 top=surface(p)
 if top is None:continue
 stats['exposed_cells']+=1
 for dx,dz in [(1,0),(0,1)]:
  for dy in [-1,0,1]:
   q=(p[0]+dx,p[1]+dy,p[2]+dz);other=surface(q)
   if other is None:continue
   if dy==0:
    reason='same_layer_connected' if joined(p,q) else 'same_layer_separated'
   else:
    high,low=(p,q) if p[1]>q[1] else (q,p)
    under=(high[0],high[1]-1,high[2]);h=cells[high];u=cells.get(under)
    if h[0]!=0:reason='cross_layer_solid_floor'
    elif not u:reason='cross_layer_unknown_under'
    elif u[1]!=500:reason='cross_layer_solid_ceiling'
    elif u[2]<(u[1]-u[0])*250:reason='cross_layer_under_not_full'
    elif not joined(under,low):reason='cross_layer_no_shared_wet_opening'
    else:reason='cross_layer_connected'
   stats[reason]+=1
   if 'not_full' in reason and len(examples)<10:examples.append({'p':p,'q':q,'heights':[top,other],'under':u,'deficit_ml':(u[1]-u[0])*250-u[2]})
report={'counts':dict(stats),'examples':examples,'scope':'Exposed adjacent-column pairs in frozen store; not a visible-pixel classification.'}
(ROOT/'reports/water_surface_snapshot_analysis.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
