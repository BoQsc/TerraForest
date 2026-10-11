// SPDX-License-Identifier: 0BSD
#pragma once
#include <array>
#include <cmath>
namespace terraforest::water_clip {
struct Vertex {double x,y,z,d;double next=0;};
using Tet=std::array<Vertex,4>;
inline Vertex interpolate(const Vertex &a,const Vertex &b,double weight) {
    return {a.x+(b.x-a.x)*weight,a.y+(b.y-a.y)*weight,a.z+(b.z-a.z)*weight,a.d+(b.d-a.d)*weight,a.next+(b.next-a.next)*weight};
}
// Clip a convex tetrahedron to a half-space. At most three tetrahedra result.
inline int clip_field(const Tet &input,std::array<Tet,3> &out,int field,double fill) {
    int inside[4],outside[4],ni=0,no=0;double values[4];
    for(int k=0;k<4;++k){values[k]=field==0?input[k].d:(field==1?fill-input[k].y:input[k].next);if(values[k]>0)inside[ni++]=k;else outside[no++]=k;}
    if(!ni)return 0;if(ni==4){out[0]=input;return 1;}
    auto edge=[&](int i,int j){return interpolate(input[i],input[j],values[i]/(values[i]-values[j]));};
    const auto a=input[inside[0]];
    if(ni==1){out[0]={a,edge(inside[0],outside[0]),edge(inside[0],outside[1]),edge(inside[0],outside[2])};return 1;}
    const auto b=input[inside[1]];
    if(ni==3){
        const auto c=input[inside[2]],p=edge(inside[0],outside[0]),q=edge(inside[1],outside[0]),r=edge(inside[2],outside[0]);
        out[0]={a,b,c,p};out[1]={b,c,p,q};out[2]={c,p,q,r};return 3;
    }
    const auto p=edge(inside[0],outside[0]),q=edge(inside[0],outside[1]),r=edge(inside[1],outside[0]),s=edge(inside[1],outside[1]);
    out[0]={a,p,q,b};out[1]={p,q,b,r};out[2]={q,b,r,s};return 3;
}
inline int clip(const Tet &input,std::array<Tet,3> &out,bool density,double fill){return clip_field(input,out,density?0:1,fill);}
inline double volume(const Tet &t) {
    const double ax=t[1].x-t[0].x,ay=t[1].y-t[0].y,az=t[1].z-t[0].z;
    const double bx=t[2].x-t[0].x,by=t[2].y-t[0].y,bz=t[2].z-t[0].z;
    const double cx=t[3].x-t[0].x,cy=t[3].y-t[0].y,cz=t[3].z-t[0].z;
    return std::abs(ax*(by*cz-bz*cy)-ay*(bx*cz-bz*cx)+az*(bx*cy-by*cx))/6.0;
}
}
