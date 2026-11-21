// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_cell_profile.hpp"
#include <tuple>

namespace terraforest {
// Horizontal section of one monotone triangle. Heights stay in millimetres
// until projection. The lower cell needs liquid immediately below the plane.
// A cell across its upper face needs air immediately above that same plane.
inline WaterFaceClip::Polygon water_floor_section(const WaterCellProfile::Triangle &t,double height,bool above){
    WaterFaceClip::Polygon polygon;
    for(int edge=0;edge<3;++edge){
        auto a=t[edge],b=t[(edge+1)%3];
        bool inside=above?a.y<=height:a.y<height;
        bool next=above?b.y<=height:b.y<height;
        if(inside)polygon.append({a.x*.5,a.z*.5});
        if(inside!=next){
            if(std::tie(b.x,b.z,b.y)<std::tie(a.x,a.z,a.y))std::swap(a,b);
            double f=(height-a.y)/(b.y-a.y);
            polygon.append({(a.x+(b.x-a.x)*f)*.5,(a.z+(b.z-a.z)*f)*.5});
        }
    }
    // Intersection clips to the left of each oriented edge. Contacts read
    // from terrain can have either winding.
    double signed_area=0;
    for(size_t i=0;i<polygon.count;++i){
        auto a=polygon[i],b=polygon[(i+1)%polygon.count];
        signed_area+=a.x*b.y-a.y*b.x;
    }
    if(signed_area<0)std::reverse(polygon.local.begin(),polygon.local.begin()+polygon.count);
    return polygon;
}

// Intersect a piecewise-linear free surface with a piecewise-linear bed in
// the horizontal plane. Both keep their original triangle diagonals. A point
// in the overlap is wet exactly when the bed lies below the free surface.
template<class Emit> void water_cap_sections(const WaterCellProfile &bed,const std::array<double,4> &h,Emit emit){
    using F=WaterFaceClip;
    using C=WaterSolidClip;
    const C::Point corners[]={{0,h[0],0},{.5,h[1],0},{0,h[2],.5},{.5,h[3],.5}};
    for(auto ids:{std::array<int,3>{0,1,3},std::array<int,3>{0,3,2}}){
        const auto a=corners[ids[0]],b=corners[ids[1]],c=corners[ids[2]];
        auto normal=(c-a).cross(b-a);normal=normal*(1./std::sqrt(normal.dot(normal)));
        C::Plane cap{normal,normal.dot(a)};
        F::Polygon triangle;
        for(auto p:{a,b,c})triangle.append({p.x,p.z});
        bed.floor_triangles([&](const WaterCellProfile::Triangle &floor){
            C::Point v[3];
            for(int i=0;i<3;++i)v[i]={floor[i].x*.5,floor[i].y*.001,floor[i].z*.5};
            auto up=(v[2]-v[0]).cross(v[1]-v[0]);
            if(std::abs(up.y)<1e-15)return;
            if(up.y<0){std::swap(v[1],v[2]);up=up*(-1);}
            F::Polygon footprint;
            for(auto p:v)footprint.append({p.x,p.z});
            auto wet=triangle;
            if(!F::intersect(wet,footprint))return;
            // y_bed - y_cap <= 0. Use height-unit coefficients so the
            // clipping tolerance is independent of either triangle's area.
            const double dx=normal.x/normal.y-up.x/up.y;
            const double dz=normal.z/normal.y-up.z/up.y;
            const double offset=cap.offset/normal.y-up.dot(v[0])/up.y;
            if(dx==0&&dz==0&&offset<=0)return;
            if(!F::clip(wet,dx,dz,offset)||wet.count<3||F::area(wet)<=1e-16)return;
            C::Face face;face.reserve(wet.count);
            for(size_t i=0;i<wet.count;++i){
                auto p=wet[i];face.push_back({p.x,(cap.offset-normal.x*p.x-normal.z*p.y)/normal.y,p.y});
            }
            emit(std::move(face),cap);
        });
    }
}
}
