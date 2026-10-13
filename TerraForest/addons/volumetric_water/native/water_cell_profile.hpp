// SPDX-License-Identifier: 0BSD
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace terraforest {
// A floor cut through a finite-volume cell. The two triangles use the same
// four cached density crossings; no new terrain queries or water store.
// Coordinates are cell-local X/Z [0,1]; heights are millimetres. Floor
// Crossings remain unclamped through interpolation. Volume clips against both
// the zero bottom and 500 mm top; corner-clamping invents solid wedges.
struct WaterCellProfile {
    struct Point { double x,z,y; };
    struct Shape { double area=0,x=0,z=0; };
    std::array<double,4> floor{}; // 00, 10, 01, 11
    double ceiling=500;
    double slope_x=0,slope_z=0; // Reconstructed free-surface slope, mm per cell.
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
    double minimum()const{return *std::min_element(floor.begin(),floor.end());}
    double maximum()const{return *std::max_element(floor.begin(),floor.end());}
    double mean()const{return (floor[0]+floor[3])/3.0+(floor[1]+floor[2])/6.0;}
    double bottom(double x,double z)const {
        x=std::clamp(x,0.0,1.0);z=std::clamp(z,0.0,1.0);
        return std::max(0.0,x>=z ? floor[0]*(1-x)+floor[1]*(x-z)+floor[3]*z
                    : floor[0]*(1-z)+floor[2]*(z-x)+floor[3]*x);
    }
    template<class Emit> void polygons(double h,Emit emit)const {
        const Point v[4]={{0,0,floor[0]},{1,0,floor[1]},{0,1,floor[2]},{1,1,floor[3]}};
        for(const auto &ids:std::array<std::array<int,3>,2>{{{{0,1,3}},{{0,3,2}}}}){
            Point clipped[4];int count=0;
            for(int e=0;e<3;++e){Point a=v[ids[e]],b=v[ids[(e+1)%3]];
                if(a.y<h)clipped[count++]=a;
                if((a.y<h)!=(b.y<h)){double t=(h-a.y)/(b.y-a.y);clipped[count++]={a.x+(b.x-a.x)*t,a.z+(b.z-a.z)*t,h};}
            }
            for(int n=1;n+1<count;++n){Point a=clipped[0],b=clipped[n],c=clipped[n+1];
                double area=std::abs((b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x))*0.5;
                emit(area,a,b,c);
            }
        }
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
    uint64_t capacity()const{return uint64_t(std::floor(flat_volume(ceiling)+1e-7));}
    double offset(double x,double z)const{return slope_x*(x-0.5)+slope_z*(z-0.5);}
    double surface(double h,double x,double z)const{return std::min(ceiling,h+offset(x,z));}
    // Integrate a positive linear field over a triangle. Clipping preserves
    // exact finite volume for a sloping surface, including wet/dry interfaces.
    template<class Emit> static void positive_triangle(Point a,Point b,Point c,Emit emit){
        Point source[3]={a,b,c},clipped[4];int count=0;
        for(int e=0;e<3;++e){Point u=source[e],v=source[(e+1)%3];
            if(u.y>0)clipped[count++]=u;
            if((u.y>0)!=(v.y>0)){double t=u.y/(u.y-v.y);clipped[count++]={u.x+(v.x-u.x)*t,u.z+(v.z-u.z)*t,0};}
        }
        for(int i=1;i+1<count;++i){Point u=clipped[0],v=clipped[i],w=clipped[i+1];
            double area=std::abs((v.x-u.x)*(w.z-u.z)-(v.z-u.z)*(w.x-u.x))*0.5;
            emit(area,u,v,w);}
    }
    template<class Emit> void air_triangles(Emit emit)const {
        polygons(ceiling,[&](double area,Point a,Point b,Point c){
            if(a.y>=0&&b.y>=0&&c.y>=0){emit(area,a,b,c);return;}
            if(a.y<=0&&b.y<=0&&c.y<=0){a.y=b.y=c.y=0;emit(area,a,b,c);return;}
            positive_triangle(a,b,c,emit);
            a.y=-a.y;b.y=-b.y;c.y=-c.y;
            positive_triangle(a,b,c,[&](double part,Point u,Point v,Point w){u.y=v.y=w.y=0;emit(part,u,v,w);});
        });
    }
    double volume(double h)const {
        if(slope_x==0&&slope_z==0)return flat_volume(h);
        double result=0;
        air_triangles([&](double,Point a,Point b,Point c){
            auto integrate=[&](bool above){
                Point u=a,v=b,w=c;
                u.y=h+offset(a.x,a.z)-(above?ceiling:a.y);
                v.y=h+offset(b.x,b.z)-(above?ceiling:b.y);
                w.y=h+offset(c.x,c.z)-(above?ceiling:c.y);
                double value=0;positive_triangle(u,v,w,[&](double area,Point p,Point q,Point r){value+=area*(p.y+q.y+r.y)/3;});return value;
            };
            result+=integrate(false)-integrate(true);
        });
        return std::max(0.0,result*250);
    }
    double head(uint64_t ml)const {
        if(slope_x==0&&slope_z==0){
            if(!ml)return std::max(0.0,minimum());
            if(ml>=flat_volume(maximum()))return std::min(ceiling,mean()+(ml+(minimum()<0?raw_volume(0):0))/250.0);
            if(ml>=capacity())return ceiling;
        }
        double lo=1e30,hi=ceiling+(std::abs(slope_x)+std::abs(slope_z))*0.5;
        for(int i=0;i<4;++i)lo=std::min(lo,floor[i]-offset(i&1,i>>1));
        if(!ml)return lo;
        for(int n=0;n<26;++n){double mid=(lo+hi)*0.5;if(volume(mid)<ml)lo=mid;else hi=mid;}
        return (lo+hi)*0.5;
    }
    Shape footprint(double h)const {
        Shape result;
        auto add=[&](double area,Point a,Point b,Point c){result.area+=area;result.x+=area*(a.x+b.x+c.x)/3;result.z+=area*(a.z+b.z+c.z)/3;};
        if(slope_x==0&&slope_z==0)polygons(h,add);
        else air_triangles([&](double,Point a,Point b,Point c){
            a.y=h+offset(a.x,a.z)-a.y;b.y=h+offset(b.x,b.z)-b.y;c.y=h+offset(c.x,c.z)-c.y;
            positive_triangle(a,b,c,add);
        });
        if(result.area>0){result.x/=result.area;result.z/=result.area;}else result.x=result.z=0.5;
        return result;
    }
    // Lowest opening on a shared face. Piecewise linear floors agree across
    // the face because they come from identical cached terrain edge samples.
    double opening(int axis,int side)const {
        if(axis==0)return side?std::min(floor[1],floor[3]):std::min(floor[0],floor[2]);
        return side?std::min(floor[2],floor[3]):std::min(floor[0],floor[1]);
    }
};
}
