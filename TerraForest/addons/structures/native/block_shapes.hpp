#pragma once
#include "block_world.hpp"
#include <cmath>

namespace terraforest {
struct ShapePlane {Vector3 normal;double offset;};
struct SphereTemplate {
    std::array<BlockVertex,91> vertices;
    std::array<int32_t,360> indices;
    std::array<ShapePlane,120> planes;
};
// Shared source for visual/collision triangles and authoritative convex queries.
inline const SphereTemplate &sphere_template() {
    static const SphereTemplate geometry=[] {
        SphereTemplate result{};constexpr double pi=3.14159265358979323846;
        for(int y=0;y<=6;y++)for(int x=0;x<=12;x++) {
            double theta=pi*y/6,phi=2*pi*(x==12?0:x)/12;
            double radial=(y==0||y==6)?0:std::sin(theta);
            Vector3 n(float(radial*std::cos(phi)),float(std::cos(theta)),float(radial*std::sin(phi)));
            Vector3 p=Vector3(.5,.5,.5)+n*.5;
            result.vertices[y*13+x]={p.x,p.y,p.z,n.x,n.y,n.z,float(3.0*x/12),float(theta*.5),0};
        }
        int index=0;
        for(int y=0;y<6;y++)for(int x=0;x<12;x++) {
            int a=y*13+x,b=a+13,c=b+1,d=a+1;
            if(y<5)for(int v:{a,b,c})result.indices[index++]=v;
            if(y>0)for(int v:{a,c,d})result.indices[index++]=v;
        }
        auto point=[&](int i){auto &v=result.vertices[result.indices[i]];return Vector3(v.x,v.y,v.z);};
        for(int i=0;i<120;i++) {
            auto a=point(i*3),b=point(i*3+1),c=point(i*3+2);
            Vector3 normal=(c-a).cross(b-a).normalized();
            result.planes[i]={normal,double(normal.dot(a))};
        }
        return result;
    }();
    return geometry;
}
struct CylinderTemplate {
    std::array<BlockVertex,54> vertices;
    std::array<int32_t,144> indices;
    std::array<ShapePlane,12> planes;
};
inline const CylinderTemplate &cylinder_template() {
    static const CylinderTemplate geometry=[] {
        CylinderTemplate result{};constexpr double pi=3.14159265358979323846;
        for(int i=0;i<=12;++i) {
            double angle=2*pi*(i==12?0:i)/12;
            float nx=float(std::cos(angle)),nz=float(std::sin(angle));
            float x=.5f+nx*.5f,z=.5f+nz*.5f;
            for(int y=0;y<2;++y) {
                result.vertices[i*2+y]={x,float(y),z,nx,0,nz,float(pi*i/12),float(y),0};
                result.vertices[26+i*2+y]={x,float(y),z,0,float(y*2-1),0,x,z,0};
            }
            if(i<12) {
                double mid=2*pi*(i+.5)/12;
                Vector3 n(float(std::cos(mid)),0,float(std::sin(mid)));
                result.planes[i]={n,.5*(n.x+n.z)+.5*std::cos(pi/12)};
            }
        }
        result.vertices[52]={.5,0,.5,0,-1,0,.5,.5,0};
        result.vertices[53]={.5,1,.5,0,1,0,.5,.5,0};
        int at=0;
        for(int i=0;i<12;++i) {
            int a=i*2,b=a+1,c=a+3,d=a+2;
            for(int v:{a,c,b,a,d,c,52,26+d,26+a,53,26+b,26+c})result.indices[at++]=v;
        }
        return result;
    }();return geometry;
}
// Shared allocation-free authored planes for picking and water occupancy.
template<class Begin,class Plane,class End>
void visit_shape_hulls(int shape,Begin begin,Plane plane,End end){
    auto planes=[&](Vector3 lo,Vector3 hi){for(int a=0;a<3;++a){Vector3 n;n[a]=1;plane(n,double(hi[a]));n[a]=-1;plane(n,-double(lo[a]));}};
    auto box=[&](Vector3 lo,Vector3 hi){begin();planes(lo,hi);end();};
    if(shape==1)box(Vector3(),Vector3(1,1,1));
    else if(shape==2)box(Vector3(),Vector3(1,.5,1));
    else if(shape==3)for(int step=0;step<4;++step)box(Vector3(0,0,step*.25),Vector3(1,(step+1)*.25,(step+1)*.25));
    else if(shape==4){begin();planes(Vector3(),Vector3(1,1,1));plane(Vector3(0,1,-1).normalized(),0);end();}
    else if(shape==5)box(Vector3(.25,0,.25),Vector3(.75,1,.75));
    else if(shape==7){begin();planes(Vector3(),Vector3(1,1,1));for(const auto &p:cylinder_template().planes)plane(p.normal,p.offset);end();}
    else if(shape==6){begin();planes(Vector3(),Vector3(1,1,1));for(const auto &p:sphere_template().planes)plane(p.normal,p.offset);end();}
}

}
