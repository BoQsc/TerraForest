# SPDX-License-Identifier: 0BSD
# Independent exact integral for nonnegative nodal tank fields. No clipping code.
# A tetrahedron with any positive vertex is positive everywhere in its interior.
# With m upper vertices, the volume below fraction f is the Beta(m,4-m) CDF.
from fractions import Fraction as F
T=((0,1,3,7),(0,1,5,7),(0,2,3,7),(0,2,6,7),(0,4,5,7),(0,4,6,7))
def reference(n,h,divide=False,roof=False):
    result=F(0)
    for y in range(h.numerator//h.denominator+1):
        counts=[0,0,0,0]
        if roof and y>=3:continue
        for z in range(n):
            for x in range(n):
                if divide and x>=4:continue
                for tet in T:
                    nodes=[(x+(c&1),y+((c>>1)&1),z+((c>>2)&1)) for c in tet]
                    if any(a not in (0,n) and c not in (0,n) and b!=0 and (not divide or a!=4) and (not roof or b!=3) for a,b,c in nodes):
                        counts[sum((c>>1)&1 for c in tet)]+=1
        f=min(F(1),max(F(0),h-y))
        result+=(counts[1]*(1-(1-f)**3)+counts[2]*(3*f*f-2*f**3)+counts[3]*f**3)/6
    return result
if __name__=='__main__':
    for n,h,d,r in [(8,F(9,2),False,False),(8,F(9,2),True,False),(8,F(9,2),False,True),(64,F(97,2),False,False)]:
        result=reference(n,h,d,r);print(n,d,r,result,round(result*1000000))
