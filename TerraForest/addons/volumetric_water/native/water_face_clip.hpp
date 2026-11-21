// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_solid_clip.hpp"
#include <array>
#include <memory>
namespace terraforest {
struct WaterFaceClip {
    struct Point {double x,y;};
    // Most shared faces are triangles or quads. Keep the full complexity
    // bound without copying 8 KiB at every plane of every hull.
    struct Polygon {
        static constexpr size_t INLINE=16,LIMIT=512;
        std::array<Point,INLINE> local;
        std::unique_ptr<Point[]> overflow;
        size_t count=0;
        Polygon()=default;
        Polygon(const Polygon &p){assign(p.data(),p.count);}
        Polygon &operator=(const Polygon &p){if(this!=&p)assign(p.data(),p.count);return *this;}
        const Point *data()const{return overflow?overflow.get():local.data();}
        const Point &operator[](size_t i)const{return data()[i];}
        void assign(const Point *points,size_t n){
            if(n>INLINE&&!overflow)overflow.reset(new Point[LIMIT]);
            std::copy_n(points,n,overflow?overflow.get():local.data());
            count=n;
        }
        bool append(Point value){
            if(count==LIMIT)return false;
            if(count==INLINE&&!overflow){
                overflow.reset(new Point[LIMIT]);
                std::copy_n(local.data(),count,overflow.get());
            }
            (overflow?overflow.get():local.data())[count++]=value;
            return true;
        }
    };
    static Polygon square(){Polygon p;p.append({0,0});p.append({.5,0});p.append({.5,.5});p.append({0,.5});return p;}
    static double area(const Polygon &p){double v=0;for(size_t i=0;i<p.count;++i){auto a=p[i],b=p[(i+1)%p.count];v+=a.x*b.y-a.y*b.x;}return std::abs(v)*.5;}
    static bool clip(Polygon &p,double nx,double ny,double offset){
        Polygon out;
        auto append=[&](Point v){return out.append(v);};
        for(size_t i=0;i<p.count;++i){auto a=p[i],b=p[(i+1)%p.count];double da=nx*a.x+ny*a.y-offset,db=nx*b.x+ny*b.y-offset;
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
    static bool intersect(Polygon &a,const Polygon &b){
        for(size_t i=0;i<b.count&&a.count>=3;++i){auto p=b[i],q=b[(i+1)%b.count];double nx=q.y-p.y,ny=p.x-q.x;
            if(!clip(a,nx,ny,nx*p.x+ny*p.y))return false;}
        return a.count>=3&&area(a)>1e-12;
    }
    static bool overlaps(Polygon a,const Polygon &b){return intersect(a,b);}
};
}
