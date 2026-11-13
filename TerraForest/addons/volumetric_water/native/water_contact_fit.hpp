// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/vector3.hpp>
#include <algorithm>
#include <cmath>

namespace terraforest {
// Bounded Hermite fit for a solid/free-surface intersection. Topology and owner
// masks remain with the shared extractor. Evaluate the actual clipped field,
// rather than averaging crossings into a bevel around the object's waterline.
template<class Sample>
godot::Vector3 fit_water_contact(const float *density,unsigned component,godot::Vector3 anchor,Sample sample){
    static constexpr int edges[12][2]={{0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7}};
    double system[3][4]{};
    for(int e=0;e<12;++e)if(component&(1u<<(8+e))){
        int a=edges[e][0],b=edges[e][1];
        godot::Vector3 left(a&1,(a>>1)&1,(a>>2)&1),right(b&1,(b>>1)&1,(b>>2)&1);
        if(density[a]>=0)std::swap(left,right);
        for(int iteration=0;iteration<12;++iteration){
            auto middle=(left+right)*.5f;
            // Internal cell faces may be exactly zero on both wet sides.
            if(sample(middle)<=1e-9)left=middle;else right=middle;
        }
        const auto point=(left+right)*.5f;
        constexpr float epsilon=.004f;
        godot::Vector3 normal;
        for(int axis=0;axis<3;++axis){godot::Vector3 delta;delta[axis]=epsilon;normal[axis]=sample(point+delta)-sample(point-delta);}
        if(normal.length_squared()<1e-16)continue;
        normal.normalize();const double target=normal.dot(point-anchor);
        for(int i=0;i<3;++i){for(int j=0;j<3;++j)system[i][j]+=normal[i]*normal[j];system[i][3]+=normal[i]*target;}
    }
    // Anchor only unconstrained directions; the tiny regularizer prevents a
    // planar face from drifting while preserving its sharp intersection.
    for(int i=0;i<3;++i)system[i][i]+=1e-6;
    for(int axis=0;axis<3;++axis){
        int pivot=axis;for(int row=axis+1;row<3;++row)if(std::abs(system[row][axis])>std::abs(system[pivot][axis]))pivot=row;
        for(int j=axis;j<4;++j)std::swap(system[axis][j],system[pivot][j]);
        double scale=system[axis][axis];if(std::abs(scale)<1e-12)return anchor;
        for(int j=axis;j<4;++j)system[axis][j]/=scale;
        for(int row=0;row<3;++row)if(row!=axis){double factor=system[row][axis];for(int j=axis;j<4;++j)system[row][j]-=factor*system[axis][j];}
    }
    for(int i=0;i<3;++i)anchor[i]=std::clamp(double(anchor[i])+system[i][3],0.0,1.0);
    return anchor;
}
}
