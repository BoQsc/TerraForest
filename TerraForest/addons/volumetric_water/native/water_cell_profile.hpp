// SPDX-License-Identifier: 0BSD
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>
#include "water_solid_profile.hpp"

namespace terraforest {
// A floor cut through a finite-volume cell. The two triangles use the same
// four cached density crossings; no new terrain queries or water store.
// Coordinates are cell-local X/Z [0,1]; heights are millimetres. Floor
// Crossings remain unclamped through interpolation. Volume clips against both
// the zero bottom and 500 mm top; corner-clamping invents solid wedges.
struct WaterCellProfile {
    const WaterSolidProfile *solid=nullptr; // Immutable prepared building occupancy.
    struct Point { double x,z,y; };
    using Triangle=std::array<Point,3>;
    const std::vector<Triangle> *contact=nullptr; // Immutable terrain-owned floor fragments.
    struct Shape { double area=0,x=0,z=0; };
    std::array<double,4> floor{}; // 00, 10, 01, 11
    double ceiling=500;
    bool cut=false,open_bottom=true;
    static WaterCellProfile make(const float *d,bool shaped,uint16_t lo,uint16_t hi) {
        WaterCellProfile p;p.floor.fill(lo);p.ceiling=hi;p.open_bottom=lo==0;
        // Upward-monotone floor crossings remain a single air interval even
        // where the floor rises above the cell top. Retain those crossings
        // beyond 500 mm so clipping computes the actual partial top opening.
        // Ambiguous walls/ceilings keep the conservative interval.
        if(!shaped)return p;
        bool all_air=true;for(int n=0;n<8;++n)all_air&=d[n]>0;
        if(all_air){p.floor.fill(0);p.ceiling=500;p.open_bottom=true;p.cut=true;return p;}
        std::array<double,4> crossings{};bool open=false;
        for(int n=0;n<4;++n){int i=(n&1)+4*(n>>1);
            double a=d[i],b=d[i+2];
            if(b>a)crossings[n]=500.0*(-a)/(b-a);
            else if(a>=0&&b>0)crossings[n]=0;
            else return p;
            open|=a>0;
        }
        p.floor=crossings;p.ceiling=500;p.open_bottom=open;p.cut=true;return p;
    }
    template<class Emit> void floor_triangles(Emit emit)const {
        if(contact){for(const auto &t:*contact)emit(t);return;}
        const Point v[4]={{0,0,floor[0]},{1,0,floor[1]},{0,1,floor[2]},{1,1,floor[3]}};
        emit(Triangle{v[0],v[1],v[3]});emit(Triangle{v[0],v[3],v[2]});
    }
    double minimum()const{double v=1e30;floor_triangles([&](const Triangle&t){for(auto p:t)v=std::min(v,p.y);});return v;}
    double maximum()const{double v=-1e30;floor_triangles([&](const Triangle&t){for(auto p:t)v=std::max(v,p.y);});return v;}
    double mean()const{double v=0;floor_triangles([&](const Triangle&t){auto a=t[0],b=t[1],c=t[2];double area=std::abs((b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x))*0.5;v+=area*(a.y+b.y+c.y)/3;});return v;}
    double raw_bottom(double x,double z)const {
        x=std::clamp(x,0.0,1.0);z=std::clamp(z,0.0,1.0);
        if(contact)for(const auto&t:*contact){auto a=t[0],b=t[1],c=t[2];double det=(b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x);if(std::abs(det)<1e-12)continue;
            double u=((x-a.x)*(c.z-a.z)-(z-a.z)*(c.x-a.x))/det,v=((b.x-a.x)*(z-a.z)-(b.z-a.z)*(x-a.x))/det;
            if(u>=-1e-7&&v>=-1e-7&&u+v<=1+1e-7)return a.y+u*(b.y-a.y)+v*(c.y-a.y);}
        return x>=z ? floor[0]*(1-x)+floor[1]*(x-z)+floor[3]*z : floor[0]*(1-z)+floor[2]*(z-x)+floor[3]*x;
    }
    double bottom(double x,double z)const{return std::max(0.0,raw_bottom(x,z));}
    template<class Emit> void polygons(double h,Emit emit)const {
        floor_triangles([&](const Triangle&v){
            Point clipped[4];int count=0;
            for(int e=0;e<3;++e){Point a=v[e],b=v[(e+1)%3];
                if(a.y<h)clipped[count++]=a;
                if((a.y<h)!=(b.y<h)){double t=(h-a.y)/(b.y-a.y);clipped[count++]={a.x+(b.x-a.x)*t,a.z+(b.z-a.z)*t,h};}
            }
            for(int n=1;n+1<count;++n){Point a=clipped[0],b=clipped[n],c=clipped[n+1];
                double area=std::abs((b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x))*0.5;emit(area,a,b,c);}
        });
    }
    // Exact editable air geometry for structure replacement. Coordinates passed
    // to solids are local metres, matching the half-metre cell. This also keeps
    // both remaining intervals when an object cuts through the middle of water.
    bool solid_remainder(double head,const std::vector<std::vector<WaterSolidClip::Plane>> &solids,
                         WaterSolidClip::Pieces &out)const {
        using C=WaterSolidClip;C::Pieces pieces;bool ok=std::isfinite(head);
        const double top=std::clamp(head,0.0,ceiling)*.001;
        if(!ok||solids.size()>C::MAX_PIECES)return false;
        if(top<=0){out.clear();return true;}
        floor_triangles([&](const Triangle &t){
            if(!ok)return;
            C::Point a{t[0].x*.5,0,t[0].z*.5},b{t[1].x*.5,0,t[1].z*.5},c{t[2].x*.5,0,t[2].z*.5};
            C::Point u{0,top,0};
            C::Polyhedron prism{{{a,b,c},{a+u,c+u,b+u},{a,a+u,b+u,b},{b,b+u,c+u,c},{c,c+u,a+u,a}}};
            C::Point fa=a,fb=b,fc=c;fa.y=t[0].y*.001;fb.y=t[1].y*.001;fc.y=t[2].y*.001;
            C::Point n=(fb-fa).cross(fc-fa);if(std::abs(n.y)<1e-15)return;
            if(n.y>0)n=n*(-1); // Keep air above the floor.
            C::Polyhedron clipped;
            if(!C::clip(prism,{n,n.dot(fa)},clipped)){ok=false;return;}
            if(C::volume(clipped)>1e-15){if(pieces.size()==C::MAX_PIECES){ok=false;return;}pieces.push_back(std::move(clipped));}
        });
        if(!ok)return false;
        for(const auto &solid:solids){C::Pieces next;if(!C::subtract(pieces,solid,next))return false;pieces=std::move(next);}
        out=std::move(pieces);return true;
    }
    double raw_volume(double h)const {
        h=std::min(h,ceiling);if(h<=minimum())return 0;
        if(h>=maximum())return (h-mean())*250;
        double result=0;
        polygons(h,[&](double area,Point a,Point b,Point c){result+=area*(h-(a.y+b.y+c.y)/3.0)*250;});
        return std::max(0.0,result);
    }
    double flat_volume(double h)const {
        if(h<=0)return 0;
        return std::max(0.0,raw_volume(h)-(minimum()<0?raw_volume(0):0));
    }
    uint64_t capacity()const{if(solid)return uint64_t(std::floor(solid->capacity()*1000000+1e-7));return uint64_t(std::floor(flat_volume(ceiling)+1e-7));}
    // Static occupancy has a horizontal top; only its cached terrain floor varies.
    double surface(double h,double,double)const{return std::min(ceiling,h);}
    double volume(double h)const{return solid?solid->volume(h*.001)*1000000:flat_volume(h);}
    double head(uint64_t ml)const {
        if(solid)return solid->head(double(ml)*.000001)*1000;
            if(!ml)return std::max(0.0,minimum());
            if(ml>=capacity())return ceiling;
            if(ml>=flat_volume(maximum()))return std::min(ceiling,mean()+(ml+(minimum()<0?raw_volume(0):0))/250.0);
        double lo=1e30,hi=ceiling;
        for(int i=0;i<4;++i)lo=std::min(lo,floor[i]);
        if(!ml)return lo;
        for(int n=0;n<26;++n){double mid=(lo+hi)*0.5;if(volume(mid)<ml)lo=mid;else hi=mid;}
        return (lo+hi)*0.5;
    }
    // Cell-local metres; head remains millimetres like the volume API.
    double field(double x,double y,double z,double h)const {
        if(solid)return solid->distance({x,y,z},h*.001);
        return std::max({std::abs(x-.25)-.25,std::abs(z-.25)-.25,bottom(x*2,z*2)*.001-y,y-surface(h,x*2,z*2)*.001});
    }
    bool wet_interval(double x,double y,double z,double h,double &lo,double &hi)const {
        if(solid)return solid->interval({x,y,z},h*.001,lo,hi);
        lo=bottom(x*2,z*2)*.001;hi=surface(h,x*2,z*2)*.001;
        return y>=lo&&y<=hi&&hi>lo;
    }
    Shape footprint(double h)const {
        Shape result;
        auto add=[&](double area,Point a,Point b,Point c){result.area+=area;result.x+=area*(a.x+b.x+c.x)/3;result.z+=area*(a.z+b.z+c.z)/3;};
        polygons(h,add);
        if(result.area>0){result.x/=result.area;result.z/=result.area;}else result.x=result.z=0.5;
        return result;
    }
    // Exact overlap of two wet intervals along a shared horizontal face.
    // All inequalities are linear before floor/ceiling clipping.
    static bool face_overlap(const WaterCellProfile &a,double ah,const WaterCellProfile &b,double bh,int axis,int side){
        std::array<double,770> breaks;size_t count=2;breaks[0]=0;breaks[1]=1;
        auto split=[&](const WaterCellProfile &shape,int face){if(!shape.contact)return;
            for(const auto&t:*shape.contact)for(auto p:t)if(std::abs((axis==0?p.x:p.z)-face)<1e-7)breaks[count++]=std::clamp(axis==0?p.z:p.x,0.0,1.0);};
        split(a,side);split(b,1-side);std::sort(breaks.begin(),breaks.begin()+count);
        for(size_t segment=1;segment<count;++segment){
            if(breaks[segment]-breaks[segment-1]<1e-9)continue;
            double lower[3][2]{},upper[4][2]{};
            for(int t=0;t<2;++t){double along=breaks[segment-1+t],ax=axis==0?side:along,az=axis==0?along:side;
                double bx=axis==0?1-side:along,bz=axis==0?along:1-side;
                lower[0][t]=a.raw_bottom(ax,az);lower[1][t]=b.raw_bottom(bx,bz);
                upper[0][t]=ah;upper[1][t]=bh;
                upper[2][t]=a.ceiling;upper[3][t]=b.ceiling;}
            double lo=0,hi=1;bool possible=true;
            for(auto &u:upper)for(auto &l:lower){double v0=u[0]-l[0]-1e-6,v1=u[1]-l[1]-1e-6;
                if(v0<=0&&v1<=0){possible=false;continue;}
                if(v0<=0)lo=std::max(lo,-v0/(v1-v0));else if(v1<=0)hi=std::min(hi,v0/(v0-v1));}
            if(possible&&lo<hi)return true;
        }
        return false;
    }
    static bool vertical_overlap(const WaterCellProfile &low,double lh,const WaterCellProfile &high,double hh){
        const Point v[4]={{0,0,0},{1,0,0},{0,1,0},{1,1,0}};
        for(auto ids:std::array<std::array<int,3>,2>{{{{0,1,3}},{{0,3,2}}}}){
            std::array<Point,8> polygon{},next{};int count=3;
            for(int i=0;i<3;++i)polygon[i]=v[ids[i]];
            for(int constraint=0;constraint<4&&count;++constraint){
                auto field=[&](Point p){switch(constraint){
                    case 0:return lh-500+1e-6;
                    case 1:return -high.raw_bottom(p.x,p.z)+1e-6;
                    case 2:return hh-1e-6;
                    default:return 500-low.raw_bottom(p.x,p.z)-1e-6;}};
                int size=0;for(int i=0;i<count;++i){Point a=polygon[i],b=polygon[(i+1)%count];double av=field(a),bv=field(b);
                    if(av>=0)next[size++]=a;
                    if((av>=0)!=(bv>=0)){double t=av/(av-bv);next[size++]={a.x+(b.x-a.x)*t,a.z+(b.z-a.z)*t,0};}}
                polygon=next;count=size;
            }
            double area=0;for(int i=1;i+1<count;++i)area+=std::abs((polygon[i].x-polygon[0].x)*(polygon[i+1].z-polygon[0].z)-(polygon[i].z-polygon[0].z)*(polygon[i+1].x-polygon[0].x));
            if(area>1e-10)return true;
        }
        return false;
    }
    // Lowest opening on a shared face. Piecewise linear floors agree across
    // the face because they come from identical cached terrain edge samples.
    double opening(int axis,int side)const {
        if(axis==0)return side?std::min(floor[1],floor[3]):std::min(floor[0],floor[2]);
        return side?std::min(floor[2],floor[3]):std::min(floor[0],floor[1]);
    }
};
}
