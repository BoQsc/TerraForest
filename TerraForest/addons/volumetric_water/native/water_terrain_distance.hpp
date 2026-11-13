// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/vector3.hpp>
#include <algorithm>

namespace terraforest {
// Closest point by plane projection plus the three bounded edge projections.
// Used only in the narrow band of the authoritative terrain mesh.
inline godot::Vector3 water_triangle_closest(godot::Vector3 p,godot::Vector3 a,godot::Vector3 b,godot::Vector3 c){
    auto ab=b-a,ac=c-a,n=ab.cross(ac);
    const double squared=n.length_squared();
    if(squared>1e-16){
        auto q=p-n*(n.dot(p-a)/squared);
        double u=(q-a).cross(ac).dot(n)/squared,v=ab.cross(q-a).dot(n)/squared;
        if(u>=0&&v>=0&&u+v<=1)return q;
    }
    godot::Vector3 result=a;double distance=(p-a).length_squared();
    const godot::Vector3 points[3]={a,b,c};
    for(int edge=0;edge<3;++edge){auto start=points[edge],d=points[(edge+1)%3]-start;
        double length=d.length_squared();if(length<1e-16)continue;
        auto q=start+d*std::clamp(double((p-start).dot(d))/length,0.0,1.0);
        double candidate=(p-q).length_squared();if(candidate<distance){distance=candidate;result=q;}
    }
    return result;
}
}
