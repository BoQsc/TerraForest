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

// Over each terrain triangle and each half of the reconstructed water cap,
// both heights are affine in X/Z. Carry the two heights on the same polygon
// while clipping. This retains the original terrain intersection without
// constructing a 3D prism or intersecting pairs of projected polygons.
template<class Emit> void water_cap_sections(const WaterCellProfile &bed,const std::array<double,4> &h,Emit emit){
    using C=WaterSolidClip;
    struct Vertex {double x,z,bed,head;};
    for(int half=0;half<2;++half){
        const double dx=half?h[3]-h[2]:h[1]-h[0];
        const double dz=half?h[2]-h[0]:h[3]-h[1];
        if(std::max({h[0],h[3],h[half?2:1]})<=0||std::min({h[0],h[3],h[half?2:1]})>=.5)continue;
        C::Point normal{-2*dx,1,-2*dz};
        normal=normal*(1./std::sqrt(normal.dot(normal)));
        const C::Plane cap{normal,normal.y*h[0]};
        bed.floor_triangles([&](const WaterCellProfile::Triangle &floor){
            // A triangle clipped by four half-planes has at most seven
            // vertices. Strict crossings avoid duplicate endpoints on a plane.
            std::array<Vertex,8> polygon,scratch;
            int count=3;
            for(int i=0;i<3;++i){
                const auto &v=floor[i];
                polygon[i]={v.x,v.z,v.y*.001,h[0]+v.x*dx+v.z*dz};
            }
            auto clip=[&](auto distance){
                int size=0;
                auto a=polygon[count-1];double da=distance(a);
                for(int i=0;i<count;++i){
                    auto b=polygon[i];double db=distance(b);
                    if((da<0&&db>0)||(da>0&&db<0)){
                        const double t=da/(da-db);
                        scratch[size++]={a.x+t*(b.x-a.x),a.z+t*(b.z-a.z),
                            a.bed+t*(b.bed-a.bed),a.head+t*(b.head-a.head)};
                    }
                    if(db>=0)scratch[size++]=b;
                    a=b;da=db;
                }
                std::copy_n(scratch.begin(),size,polygon.begin());count=size;
                return count>=3;
            };
            if(!clip([half](Vertex v){return half?v.z-v.x:v.x-v.z;}))return;
            if(!clip([](Vertex v){return v.head;}))return;
            if(!clip([](Vertex v){return .5-v.head;}))return;
            if(std::none_of(polygon.begin(),polygon.begin()+count,[](Vertex v){return v.head>v.bed;}))return;
            if(!clip([](Vertex v){return v.head-v.bed;}))return;
            C::Face face;face.reserve(count);
            double area=0;
            for(int i=0;i<count;++i){
                const auto &p=polygon[i],&q=polygon[(i+1)%count];
                area+=p.x*q.z-p.z*q.x;face.push_back({p.x*.5,p.head,p.z*.5});
            }
            if(std::abs(area)>8e-16)emit(std::move(face),cap);
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
            if(shape.solid){
                // The stored Y-face axes are Z,X. The cap polygons here
                // use X,Z. Swapping axes requires reversing the winding.
                shape.solid->visit_face(1,lower?1:0,.5,[&](const F::Polygon &face){
                    F::Polygon xz;
                    for(size_t i=face.count;i>0;--i)xz.append({face[i-1].y,face[i-1].x});
                    visit(xz);return false;
                });
                return;
            }
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
