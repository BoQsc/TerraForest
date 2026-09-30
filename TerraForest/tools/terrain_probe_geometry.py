"""Shared exact-position boundary and topology-count checks for geometry probes."""
from collections import Counter
import struct

def inspect(path):
    data=path.read_bytes();nv,ni=struct.unpack_from('<II',data)
    assert len(data)==8+12*nv+4*ni and ni%3==0
    points=[data[8+12*i:20+12*i] for i in range(nv)]
    indices=struct.unpack_from('<'+str(ni)+'I',data,8+12*nv)
    edges=Counter();triangles=Counter();neighbors={}
    for i in range(0,ni,3):
        a,b,c=(points[j] for j in indices[i:i+3])
        triangles[min((a,b,c),(b,c,a),(c,a,b))]+=1
        for u,v in [(a,b),(b,c),(c,a)]:
            edges[tuple(sorted((u,v)))]+=1
            neighbors.setdefault(u,set()).add(v);neighbors.setdefault(v,set()).add(u)
    unseen=set(neighbors);components=0
    while unseen:
        components+=1;pending=[unseen.pop()]
        while pending:
            unseen_neighbors=neighbors[pending.pop()]&unseen
            unseen.difference_update(unseen_neighbors);pending.extend(unseen_neighbors)
    topology=dict(components=components,euler=len(neighbors)-len(edges)+sum(triangles.values()),overused_edges=sum(n>2 for n in edges.values()))
    return Counter({e:n for e,n in edges.items() if n==1}),triangles,topology

