#pragma once
#include <cmath>
#include <cstdint>

namespace terraforest {
inline int select_terrain_placement(const float point[3],const float normal[3],const int origin[3],const uint32_t empty[4],int selected[3]) {
    float magnitude=0;
    int center[3];
    for(int axis=0;axis<3;axis++){
        if(!std::isfinite(point[axis])||!std::isfinite(normal[axis])||std::abs(point[axis])>10000)return -1;
        center[axis]=int(std::floor(point[axis]+.5f));
        if(center[axis]<origin[axis]+1||center[axis]>origin[axis]+3)return -1;
        magnitude+=normal[axis]*normal[axis];
    }
    if(magnitude<.25f||magnitude>2.25f)return -1;
    float scale=1.f/std::sqrt(magnitude),best=1e30f;
    bool found=false;
    for(int offset_z=-1;offset_z<=1;offset_z++)for(int offset_y=-1;offset_y<=1;offset_y++)for(int offset_x=-1;offset_x<=1;offset_x++){
        int candidate[3]={center[0]+offset_x,center[1]+offset_y,center[2]+offset_z};
        int index=candidate[0]-origin[0]+5*(candidate[1]-origin[1]+5*(candidate[2]-origin[2]));
        if(!(empty[index/32]&(uint32_t(1)<<(index%32))))continue;
        float outward=0,distance_squared=0;
        for(int axis=0;axis<3;axis++){
            float offset=float(candidate[axis])-point[axis];
            outward+=offset*normal[axis]*scale;distance_squared+=offset*offset;
        }
        if(outward<.04f||distance_squared>2.5f)continue;
        float score=2.f*distance_squared-outward*outward;
        if(score>=best)continue;
        best=score;found=true;
        for(int axis=0;axis<3;axis++)selected[axis]=candidate[axis];
    }
    return found?1:0;
}
}
