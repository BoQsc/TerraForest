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
}
