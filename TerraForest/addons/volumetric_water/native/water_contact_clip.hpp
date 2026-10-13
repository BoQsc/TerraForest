// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_cell_profile.hpp"
#include <godot_cpp/variant/vector3.hpp>
namespace terraforest {
// Clip an existing material surface against a cell and its cached terrain floor.
// All intersections use cell-local doubles; no density resampling, lifted
// vertices, stored-volume changes, scene queries or allocation in this routine.
struct WaterContactPolygon {
    struct Point{double x,y,z;};
    std::array<Point,24> points{};int count=0;
    template<class Field> void clip(Field field){
        std::array<Point,24> next{};int size=0;
        for(int i=0;i<count;++i){auto a=points[i],b=points[(i+1)%count];double av=field(a),bv=field(b);
            if(av>=0)next[size++]=a;
            if((av>=0)!=(bv>=0)){double t=av/(av-bv);next[size++]={a.x+t*(b.x-a.x),a.y+t*(b.y-a.y),a.z+t*(b.z-a.z)};}}
        points=next;count=size;
    }
};
template<class Emit> bool clip_water_contact(godot::Vector3 a,godot::Vector3 b,godot::Vector3 c,godot::Vector3 origin,const std::vector<WaterCellProfile::Triangle>*contacts,Emit emit,bool probe=false){
    WaterContactPolygon cell;cell.count=3;int i=0;
    for(auto p:{a,b,c})cell.points[i++]={double(p.x)-origin.x,double(p.y)-origin.y,double(p.z)-origin.z};
    for(int plane=0;plane<6&&cell.count>=3;++plane)cell.clip([&](auto p){switch(plane){case 0:return p.x;case 1:return .5-p.x;case 2:return p.y;case 3:return .5-p.y;case 4:return p.z;default:return .5-p.z;}});
    if(cell.count<3)return false;
    auto output=[&](const WaterContactPolygon &p){
        auto world=[&](auto q){return origin+godot::Vector3(q.x,q.y,q.z);};
        for(int j=1;j+1<p.count;++j){auto u=world(p.points[0]),v=world(p.points[j]),w=world(p.points[j+1]);
            if((v-u).cross(w-u).length_squared()>1e-16)emit(u,v,w);}
    };
    if(!contacts){if(!probe)output(cell);return false;}
    for(const auto &triangle:*contacts){
        WaterContactPolygon clipped=cell;auto a=triangle[0],b=triangle[1],c=triangle[2];
        double det=(b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x);if(std::abs(det)<1e-12)continue;
        for(int edge=0;edge<3&&clipped.count>=3;++edge){auto u=triangle[edge],v=triangle[(edge+1)%3];
            clipped.clip([&](auto p){return ((v.x-u.x)*(p.z*2-u.z)-(v.z-u.z)*(p.x*2-u.x))*(det>0?1:-1);});}
        auto above=[&](auto p){double u=((p.x*2-a.x)*(c.z-a.z)-(p.z*2-a.z)*(c.x-a.x))/det,v=((b.x-a.x)*(p.z*2-a.z)-(b.z-a.z)*(p.x*2-a.x))/det;
            return p.y-(a.y+u*(b.y-a.y)+v*(c.y-a.y))*.001;};
        if(probe){if(clipped.count>=3)for(int j=0;j<clipped.count;++j)if(above(clipped.points[j])< -1e-9)return true;continue;}
        clipped.clip(above);output(clipped);
    }
    return false;
}
}
