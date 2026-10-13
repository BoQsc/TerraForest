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
// crossings may exceed the 500 mm cell top and are clipped by volume().
struct WaterCellProfile {
    struct Point { double x,z,y; };
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
        std::array<double,4> crossings{};bool open=false;
        for(int n=0;n<4;++n){int i=(n&1)+4*(n>>1);
            double a=d[i],b=d[i+2];
            if(a>=0&&b>0)crossings[n]=0;
            else if(b>a)crossings[n]=500.0*(-a)/(b-a);
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
        return x>=z ? floor[0]*(1-x)+floor[1]*(x-z)+floor[3]*z
                    : floor[0]*(1-z)+floor[2]*(z-x)+floor[3]*x;
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
    double volume(double h)const {
        h=std::min(h,ceiling);if(h<=minimum())return 0;
        if(h>=maximum())return (h-mean())*250;
        double result=0;
        polygons(h,[&](double area,Point a,Point b,Point c){result+=area*(h-(a.y+b.y+c.y)/3.0)*250;});
        return std::max(0.0,result);
    }
    uint64_t capacity()const{return uint64_t(std::floor(volume(ceiling)+1e-7));}
    double head(uint64_t ml)const {
        if(!ml)return minimum();
        if(ml>=volume(maximum()))return std::min(ceiling,mean()+ml/250.0);
        if(ml>=capacity())return ceiling;
        double lo=minimum(),hi=ceiling;
        for(int n=0;n<24;++n){double mid=(lo+hi)*0.5;if(volume(mid)<ml)lo=mid;else hi=mid;}
        return (lo+hi)*0.5;
    }
    Shape footprint(double h)const {
        Shape result;
        polygons(h,[&](double area,Point a,Point b,Point c){result.area+=area;result.x+=area*(a.x+b.x+c.x)/3;result.z+=area*(a.z+b.z+c.z)/3;});
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
