# SPDX-License-Identifier: 0BSD
"""Bake tiny closed irregular chip meshes once; runtime only loads shared resources."""
from pathlib import Path
import math
import random

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'addons/impact_effects/art'
PHI = (1 + math.sqrt(5))/2
VERTICES = [(-1,PHI,0),(1,PHI,0),(-1,-PHI,0),(1,-PHI,0),
            (0,-1,PHI),(0,1,PHI),(0,-1,-PHI),(0,1,-PHI),
            (PHI,0,-1),(PHI,0,1),(-PHI,0,-1),(-PHI,0,1)]
FACES = [(0,11,5),(0,5,1),(0,1,7),(0,7,10),(0,10,11),
         (1,5,9),(5,11,4),(11,10,2),(10,7,6),(7,1,8),
         (3,9,4),(3,4,2),(3,2,6),(3,6,8),(3,8,9),
         (4,9,5),(2,4,11),(6,2,10),(8,6,7),(9,8,1)]

for name, seed, scales in [('stone_chip', 41, (1.0,.55,.8)), ('soil_clod', 73, (.9,.8,1.0))]:
    rng = random.Random(seed)
    points = []
    for v in VERTICES:
        radius = rng.uniform(.68,1.13)*.5/math.sqrt(1+PHI*PHI)
        points.append(tuple(v[i]*radius*scales[i] for i in range(3)))
    lines = ['# SPDX-License-Identifier: 0BSD', '# Offline baked closed 20-face fragment', 'o '+name]
    for p in points: lines.append('v %.7f %.7f %.7f'%p)
    for face in FACES:
        a,b,c = (points[i] for i in face)
        u = [b[i]-a[i] for i in range(3)]; v = [c[i]-a[i] for i in range(3)]
        n = [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        length = math.sqrt(sum(x*x for x in n)); n = [x/length for x in n]
        lines.append('vn %.7f %.7f %.7f'%tuple(n))
        axes = [i for i in range(3) if i != max(range(3),key=lambda i:abs(n[i]))]
        for p in (a,b,c):lines.append('vt %.7f %.7f'%(p[axes[0]]+.5,p[axes[1]]+.5))
    for i,face in enumerate(FACES):
        lines.append('f '+' '.join(f'{index+1}/{i*3+j+1}/{i+1}' for j,index in enumerate(face)))
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/(name+'.obj')).write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(name, '20 triangles, shared cached mesh')
