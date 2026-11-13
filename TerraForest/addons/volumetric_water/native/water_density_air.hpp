// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_solid_clip.hpp"
namespace terraforest {
// General local 3D air for non-monotone terrain cells. Six consistently split
// tetrahedra preserve walls/ceilings; ordinary floor contacts retain their
// terrain-owned triangle shortcut. Only edit-time preparation clips geometry.
inline bool water_density_air(const float *density,WaterSolidClip::Pieces &out){
    using C=WaterSolidClip;C::Pieces pieces;
    constexpr int tetrahedra[6][4]={{0,1,3,7},{0,1,5,7},{0,2,3,7},{0,2,6,7},{0,4,5,7},{0,4,6,7}};
    for(const auto &indices:tetrahedra){
        C::Point p[4];bool air=false,solid=false;
        for(int i=0;i<4;++i){int corner=indices[i];p[i]={double(corner&1)*.5,double((corner>>1)&1)*.5,double((corner>>2)&1)*.5};air|=density[corner]>0;solid|=density[corner]<=0;}
        if(!air)continue;
        C::Polyhedron tetra;
        for(int opposite=0;opposite<4;++opposite){
            int face[3],count=0;for(int i=0;i<4;++i)if(i!=opposite)face[count++]=i;
            auto a=p[face[0]],b=p[face[1]],c=p[face[2]];auto normal=(b-a).cross(c-a);
            double offset=normal.dot(a);
            if(normal.dot(p[opposite])>offset){normal=normal*(-1);offset=-offset;std::swap(b,c);}
            tetra.faces.push_back({a,b,c});tetra.planes.push_back({normal,offset});
        }
        tetra.face_planes=tetra.planes;
        if(solid){
            auto a=p[1]-p[0],b=p[2]-p[0],c=p[3]-p[0];double determinant=a.dot(b.cross(c));
            auto gradient=(b.cross(c)*(density[indices[1]]-density[indices[0]])+c.cross(a)*(density[indices[2]]-density[indices[0]])+a.cross(b)*(density[indices[3]]-density[indices[0]]))*(1/determinant);
            C::Polyhedron clipped;if(!C::clip(tetra,{gradient*(-1),density[indices[0]]-gradient.dot(p[0])},clipped))return false;
            tetra=std::move(clipped);
        }
        if(C::volume(tetra)>1e-12)pieces.push_back(std::move(tetra));
    }
    out=std::move(pieces);return true;
}
}
