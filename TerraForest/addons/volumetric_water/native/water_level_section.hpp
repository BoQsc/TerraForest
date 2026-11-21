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
        if(std::max({a.y,b.y,c.y})<=0||std::min({a.y,b.y,c.y})>=.5)continue;
        auto normal=(c-a).cross(b-a);normal=normal*(1./std::sqrt(normal.dot(normal)));
        C::Plane cap{normal,normal.dot(a)};
        F::Polygon triangle;
        for(auto p:{a,b,c})triangle.append({p.x,p.z});
        // The adjoining vertical owner emits the rest of this same plane.
        if(!F::clip(triangle,normal.x,normal.z,cap.offset)||
           !F::clip(triangle,-normal.x,-normal.z,.5*normal.y-cap.offset)||triangle.count<3)continue;
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

// A shared vertical face renders the part with water on this side and
// reachable air on the other. Intersect the two actual terrain openings
// before subtracting the neighbouring liquid, all in the face's own plane.
template<class Emit> void water_open_side(const WaterCellProfile &a,const WaterCellProfile &b,
        int axis,int side,double a0,double a1,double b0,double b1,Emit emit){
    using F=WaterFaceClip;using C=WaterSolidClip;
    if((a0<=b0&&a1<=b1)||std::max(a0,a1)<=0||std::min(b0,b1)>=.5)return;
    const C::Point upper=axis==0?C::Point{0,1,-2*(a1-a0)}:C::Point{-2*(a1-a0),1,0};
    const C::Point lower=axis==0?C::Point{0,-1,2*(b1-b0)}:C::Point{2*(b1-b0),-1,0};
    const double x=side*.5,d=side?1.:-1.;
    C::Plane plane{axis==0?C::Point{d,0,0}:C::Point{0,0,d},d*x};
    a.visit_face(axis,side,500.,[&](F::Polygon wet){
        if(!F::project(wet,{upper,a0},axis,side)||!F::project(wet,{lower,-b0},axis,side)||wet.count<3)return false;
        b.visit_face(axis,1-side,500.,[&](const F::Polygon &opening){
            auto exposed=wet;
            if(!F::intersect(exposed,opening))return false;
            C::Face face;face.reserve(exposed.count);
            for(size_t i=0;i<exposed.count;++i){
                auto p=exposed[i];face.push_back(axis==0?C::Point{x,p.x,p.y}:C::Point{p.x,p.y,x});
            }
            emit(std::move(face),plane);return false;
        });
        return false;
    });
}

template<class Emit> void water_open_horizontal(const WaterCellProfile &cell,const WaterCellProfile &other,
        const std::array<double,4> &h,const std::array<double,4> &neighbor,bool top,Emit emit){
    using F=WaterFaceClip;using C=WaterSolidClip;
    if(top&&(*std::max_element(h.begin(),h.end())<.5||*std::min_element(neighbor.begin(),neighbor.end())>0))return;
    if(!top&&(*std::max_element(h.begin(),h.end())<=0||*std::min_element(neighbor.begin(),neighbor.end())>=.5))return;
    const C::Point normal{0,top?1.:-1.,0};
    const double elevation=top?.5:0.;
    for(auto ids:{std::array<int,3>{0,1,3},std::array<int,3>{0,3,2}}){
        F::Polygon wet;
        for(int i:ids)wet.append({(i&1)*.5,(i>>1)*.5});
        // A shared triangle provides an affine extension of each column
        // head all the way to the ownership face, including dry corners.
        auto restrict=[&](const std::array<double,4> &heights,double plane,bool below,bool strict){
            if(strict&&heights[ids[0]]==plane&&heights[ids[1]]==plane&&heights[ids[2]]==plane)return false;
            const double dx=2*(ids[1]==1?heights[1]-heights[0]:heights[3]-heights[2]);
            const double dz=2*(ids[1]==1?heights[3]-heights[1]:heights[2]-heights[0]);
            const double direction=below?1.:-1.;
            return F::clip(wet,direction*dx,direction*dz,direction*(plane-heights[0]))&&wet.count>=3;
        };
        if(!restrict(h,elevation,false,!top)||!restrict(neighbor,top?0.:.5,true,!top))continue;
        auto opening=[&](const WaterCellProfile &shape,bool lower,auto visit){
            if((lower&&shape.ceiling<500)||shape.ceiling<=0)return;
            if(shape.is_full_air()){visit(F::square());return;}
            shape.floor_triangles([&](const WaterCellProfile::Triangle &t){
                auto air=water_floor_section(t,lower?500.:0.,!lower);
                if(air.count>=3&&F::area(air)>1e-12)visit(air);
            });
        };
        opening(cell,top,[&](const F::Polygon &here){
            auto occupied=wet;if(!F::intersect(occupied,here))return;
            opening(other,!top,[&](const F::Polygon &there){
                auto exposed=occupied;if(!F::intersect(exposed,there))return;
                C::Face face;face.reserve(exposed.count);
                for(size_t i=0;i<exposed.count;++i)face.push_back({exposed[i].x,elevation,exposed[i].y});
                emit(std::move(face),C::Plane{normal,top?.5:0.});
            });
        });
    }
}
}
