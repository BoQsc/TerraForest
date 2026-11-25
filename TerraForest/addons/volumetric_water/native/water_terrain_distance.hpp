// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/vector3.hpp>
#include <algorithm>

namespace terraforest {
// Closest point by plane projection plus the three bounded edge projections.
// Used only in the narrow band of the authoritative terrain mesh.
struct WaterContactTriangle {
    using Vec=godot::Vector3;
    Vec a,ab,ac,n,point[3],direction[3];
    double squared,length[3];
    WaterContactTriangle(Vec a,Vec b,Vec c):
            a(a),ab(b-a),ac(c-a),n(ab.cross(ac)),point{a,b,c},
            direction{ab,c-b,a-c},squared(n.length_squared()),
            length{direction[0].length_squared(),direction[1].length_squared(),direction[2].length_squared()}{}
    Vec closest(Vec p) const {
        if(squared>1e-16){
            auto q=p-n*(n.dot(p-a)/squared);
            double u=(q-a).cross(ac).dot(n)/squared,v=ab.cross(q-a).dot(n)/squared;
            if(u>=0&&v>=0&&u+v<=1)return q;
        }
        Vec result=a;double distance=(p-a).length_squared();
        for(int edge=0;edge<3;++edge){
            const auto &start=point[edge],&d=direction[edge];
            if(length[edge]<1e-16)continue;
            auto q=start+d*std::clamp(double((p-start).dot(d))/length[edge],0.0,1.0);
            double candidate=(p-q).length_squared();
            if(candidate<distance){distance=candidate;result=q;}
        }
        return result;
    }
};
}
