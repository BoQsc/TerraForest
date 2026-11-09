// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
bool NativeRegionalWater::dry_footprint(const Vector3 &from,const Vector3 &middle,const Vector3 &to,double radius,double vertical_offset)const{
    if(!from.is_finite()||!middle.is_finite()||!to.is_finite()||!std::isfinite(radius)||
       !std::isfinite(vertical_offset)||radius<0||radius>2||std::abs(vertical_offset)>16)return false;
    for(const auto &p:{from,middle,to})if(p.abs().length()>1000000)return false;
    Vector3 span=from-to;span.y=0;
    const double distance=span.length();
    // Route quanta are at most 1.061m; retain a bounded reusable 2m API.
    if(distance>2)return false;
    // Identical 10cm sampling, interpolation and square footprint to ActorRoute.
    // No cached water answer: edits are visible to the very next movement guard.
    const int segments=std::max(1,int(std::ceil(distance/.1)));
    const real_t extent=real_t(radius);const Vector3 shift(0,vertical_offset,0);
    static const Vector3 offsets[]={Vector3(),Vector3(1,0,0),Vector3(-1,0,0),
        Vector3(0,0,1),Vector3(0,0,-1),Vector3(1,0,1),
        Vector3(-1,0,1),Vector3(1,0,-1),Vector3(-1,0,-1)};
    for(int i=0;i<=segments;++i){
        const double t=double(i)/segments;
        const Vector3 point=t<=.5?from.lerp(middle,t*2):middle.lerp(to,(t-.5)*2);
        for(const auto &offset:offsets){
            const double depth=depth_at(point+offset*extent+shift);
            if(!std::isfinite(depth)||depth>0)return false;
        }
    }
    return true;
}
}
