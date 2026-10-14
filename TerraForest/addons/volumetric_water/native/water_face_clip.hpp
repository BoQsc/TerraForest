// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_solid_clip.hpp"
#include <array>
namespace terraforest {
struct WaterFaceClip {
    struct Point {double x=0,y=0;};
    struct Polygon {std::array<Point,512> points;size_t count=0;};
    static Polygon square(){Polygon p;p.count=4;p.points[0]={0,0};p.points[1]={.5,0};p.points[2]={.5,.5};p.points[3]={0,.5};return p;}
    static double area(const Polygon &p){double v=0;for(size_t i=0;i<p.count;++i){auto a=p.points[i],b=p.points[(i+1)%p.count];v+=a.x*b.y-a.y*b.x;}return std::abs(v)*.5;}
    static bool clip(Polygon &p,double nx,double ny,double offset){
        Polygon out;
        auto append=[&](Point v){if(out.count==out.points.size())return false;out.points[out.count++]=v;return true;};
        for(size_t i=0;i<p.count;++i){auto a=p.points[i],b=p.points[(i+1)%p.count];double da=nx*a.x+ny*a.y-offset,db=nx*b.x+ny*b.y-offset;
            bool ia=da<=1e-10,ib=db<=1e-10;
            if(ia&&!append(a))return false;
            if(ia!=ib){double t=std::clamp(da/(da-db),0.0,1.0);if(!append({a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t}))return false;}}
        p=out;return true;
    }
    static double component(WaterSolidClip::Point p,int axis){return axis==0?p.x:axis==1?p.y:p.z;}
    static bool project(Polygon &p,WaterSolidClip::Plane plane,int axis,int side){
        int u=(axis+1)%3,v=(axis+2)%3;
        return clip(p,component(plane.normal,u),component(plane.normal,v),plane.offset-component(plane.normal,axis)*side*.5);
    }
    static bool wet(Polygon &p,int axis,int side,double head){return project(p,{{0,1,0},head},axis,side);}
    static bool overlaps(Polygon a,const Polygon &b){
        for(size_t i=0;i<b.count&&a.count>=3;++i){auto p=b.points[i],q=b.points[(i+1)%b.count];double nx=q.y-p.y,ny=p.x-q.x;
            if(!clip(a,nx,ny,nx*p.x+ny*p.y))return false;}
        return a.count>=3&&area(a)>1e-12;
    }
};
}
